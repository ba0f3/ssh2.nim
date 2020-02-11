import asyncdispatch, strformat, os, posix, posix_utils
import libssh2, private/[types, utils, session]

proc initSCPClient*(ssh: SSHClient): SCPClient =
  ## Init new SCPClient instance from a SSHClient
  result.session = ssh.session
  result.socket = ssh.socket

proc uploadFile*(scp: SCPClient, localPath, remotePath: string) {.async.} =
  ## Upload a file from the local filesystem to the remote SSH server.
  var channel: Channel
  if not localPath.fileExists():
    raise newException(FileNotFoundException, &"{localPath}: No such file or directory")
  let stat = stat(localPath)
  while true:
    channel = scp.session.scpSend(remotePath, stat.st_mode.int and 777, stat.st_size)
    if channel != nil: break
    elif scp.session.sessionLastErrno() != LIBSSH2_ERROR_EAGAIN:
      let errmsg = scp.session.getLastErrorMessage()
      discard channel.channelFree()
      raise newException(SSHException, &"scp: {remotePath}: {errmsg}")

  var
    buffer: array[1024, char]
    f = open(localPath, fmRead)
  defer: f.close()
  while true:
    var bytesRead = f.readBuffer(addr buffer, buffer.len)
    if bytesRead <= 0: break

    var bytesWrite: cint
    while true:
      bytesWrite = channel.channelWrite(cast[cstring](addr buffer), bytesRead)
      if bytesWrite == LIBSSH2_ERROR_EAGAIN:
        discard waitsocket(scp.session, scp.socket)
      else:
        break
    if bytesWrite != bytesRead:
      raise newException(SSHException, &"scp: fail to write data: {bytesWrite} wrote, {bytesRead} expected")

  while channel.channelSendEof() == LIBSSH2_ERROR_EAGAIN: discard
  while channel.channelWaitEof() == LIBSSH2_ERROR_EAGAIN: discard
  while channel.channelWaitClosed() == LIBSSH2_ERROR_EAGAIN: discard
  discard channel.channelFree()

proc downloadFile*(scp: SCPClient, remotePath, localPath: string) {.async.} =
  ## Download a file from the remote SSH server to the local filesystem.
  var
    channel: Channel
    stat: Stat
    bytesRead: int
  while true:
    channel = scp.session.scpRecv(remotePath, addr stat)
    if channel != nil: break
    elif scp.session.sessionLastErrno() != LIBSSH2_ERROR_EAGAIN:
      let errmsg = scp.session.getLastErrorMessage()
      discard channel.channelFree()
      raise newException(SSHException, &"scp: {remotePath}: {errmsg}")

  var
    buffer: array[1024, char]
    f = open(localPath, fmWrite)
  defer: f.close()
  while bytesRead < stat.st_size:
    while true:
      var
        bytesToRead = buffer.len
        bytesLeft = stat.st_size - bytesRead
      if bytesLeft < bytesToRead:
        bytesToRead = bytesLeft

      zeroMem(addr buffer, buffer.len)
      let rc = channel.channelRead(addr buffer, bytesToRead)
      if rc > 0:
        let bytesWrite = f.writeBuffer(addr buffer, rc)
        if bytesWrite != rc:
          raise newException(SSHException, &"scp: fail to write data: {bytesWrite} wrote, {rc} expected")
        inc(bytesRead, rc)
      elif rc == LIBSSH2_ERROR_EAGAIN and bytesRead < stat.st_size:
        discard waitsocket(scp.session, scp.socket)
      else:
        break
  discard channel.channelFree()



