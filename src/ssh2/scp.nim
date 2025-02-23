## SCP (Secure Copy Protocol) Implementation
## ========================================
##
## This module provides SCP functionality for secure file transfers between local and remote systems.
## It implements both upload and download capabilities using the SSH protocol.
##
## Example
## -------
##
## ```nim
## import asyncdispatch
## import ssh2
## import ssh2/scp
##
## proc main() {.async.} =
##   let ssh = newSSHClient()
##   try:
##     await ssh.connect("example.com", "user", password = "pass")
##     let scp = initSCPClient(ssh)
##
##     # Upload a file
##     await scp.uploadFile("local.txt", "/remote/path/file.txt")
##
##     # Download a file
##     await scp.downloadFile("/remote/path/file.txt", "local_copy.txt")
##   finally:
##     ssh.disconnect()
##
## waitFor main()
## ```
##

import asyncdispatch, strformat, os, posix, posix_utils
import libssh2, private/[types, utils, session]

proc initSCPClient*(ssh: SSHClient): SCPClient =
  ## Creates a new SCP client from an existing SSH connection.
  ##
  ## Parameters:
  ##   ssh: An authenticated SSHClient instance
  ##
  ## Returns:
  ##   A new SCPClient instance ready for file transfers
  ##
  ## Note: The SSH connection must be established before creating an SCP client.
  result.session = ssh.session
  result.socket = ssh.socket

proc uploadFile*(scp: SCPClient, localPath, remotePath: string) {.async.} =
  ## Uploads a file from the local system to the remote server using SCP.
  ##
  ## Parameters:
  ##   localPath: Path to the local file to upload
  ##   remotePath: Destination path on the remote server
  ##
  ## Raises:
  ##   FileNotFoundException: If the local file doesn't exist
  ##   SSHException: If the transfer fails
  ##
  ## Note: File permissions are preserved during transfer
  var
    channel: libssh2.Channel
    buffer: array[1024, char]
    bytesRead: int
    bytesWrite: cint
    f: File
  if not localPath.fileExists():
    raise newException(FileNotFoundException, &"{localPath}: No such file or directory")
  let st = stat(localPath)
  while true:
    channel = scp.session.scp_send(remotePath, st.st_mode.int and 0777, st.st_size.int)
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
  ## Downloads a file from the remote server to the local system using SCP.
  ##
  ## Parameters:
  ##   remotePath: Path to the file on the remote server
  ##   localPath: Destination path on the local system
  ##
  ## Raises:
  ##   SSHException: If the file doesn't exist or transfer fails
  ##
  ## Note: File permissions from the remote file are preserved
  var
    channel: libssh2.Channel
    stat: Stat
    bytesRead: int
    buffer: array[1024, char]
    f: File
  while true:
    channel = scp.session.scp_recv(remotePath, addr stat)
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
        bytesLeft = stat.st_size.int - bytesRead
      if bytesLeft < bytesToRead:
        bytesToRead = bytesLeft
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
