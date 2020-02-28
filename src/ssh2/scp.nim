import asyncdispatch, strformat, os, posix, posix_utils
import libssh2, private/[types, utils, session]

proc initSCPClient*(ssh: SSHClient): SCPClient =
  ## Init new SCPClient instance from a SSHClient
  result.session = ssh.session
  result.socket = ssh.socket

proc uploadFile*(scp: SCPClient, localPath, remotePath: string) {.async.} =
  ## Upload a file from the local filesystem to the remote SSH server.
  var
    channel: Channel
    buffer: array[1024, char]
    bytesRead: int
    bytesWrite: cint
    f: File
  if not localPath.fileExists():
    raise newException(FileNotFoundException, &"{localPath}: No such file or directory")
  let st = stat(localPath)
  while true:
    channel = scp.session.scp_send(remotePath, st.st_mode.int and 0777, st.st_size)
    if channel != nil: break
    elif scp.session.session_last_errno() != LIBSSH2_ERROR_EAGAIN:
      let errmsg = scp.session.getLastErrorMessage()
      discard channel.channel_free()
      raise newException(SSHException, &"scp: {remotePath}: {errmsg}")
  f = open(localPath, fmRead)
  defer: f.close()
  while true:
    bytesRead = f.readBuffer(addr buffer, buffer.len)
    if bytesRead <= 0: break
    while true:
      bytesWrite = channel.channel_write(addr buffer, bytesRead)
      if bytesWrite == LIBSSH2_ERROR_EAGAIN:
        discard waitsocket(scp.session, scp.socket)
      else:
        break
    if bytesWrite != bytesRead:
      raise newException(SSHException, &"scp: fail to write data: {bytesWrite} wrote, {bytesRead} expected")

  wait(channel.channel_send_eof())
  wait(channel.channel_wait_eof())
  wait(channel.channel_wait_closed())
  discard channel.channel_free()

proc downloadFile*(scp: SCPClient, remotePath, localPath: string) {.async.} =
  ## Download a file from the remote SSH server to the local filesystem.
  var
    channel: Channel
    stat: Stat
    bytesRead: int
    buffer: array[1024, char]
    f: File
  while true:
    channel = scp.session.scp_recv2(remotePath, addr stat)
    if channel != nil:
      break
    elif scp.session.session_last_errno() != LIBSSH2_ERROR_EAGAIN:
      let errmsg = scp.session.getLastErrorMessage()
      discard channel.channel_free()
      raise newException(SSHException, &"scp: {remotePath}: {errmsg}")

  f = open(localPath, fmWrite)
  defer: f.close()
  while bytesRead < stat.st_size:
    while true:
      var
        bytesToRead = buffer.len
        bytesLeft = stat.st_size - bytesRead
      if bytesLeft < bytesToRead:
        bytesToRead = bytesLeft
      #zeroMem(addr buffer, buffer.len)
      let rc = channel.channel_read(addr buffer, bytesToRead)
      if rc > 0:
        let bytesWrite = f.writeBuffer(addr buffer, rc)
        if bytesWrite != rc:
          raise newException(SSHException, &"scp: fail to write data: {bytesWrite} wrote, {rc} expected")
        inc(bytesRead, rc)
      elif rc == LIBSSH2_ERROR_EAGAIN and bytesRead < stat.st_size:
        discard waitsocket(scp.session, scp.socket)
      else:
        break
  discard channel.channel_free()



