import asyncdispatch, strformat, os, posix, posix_utils
import libssh2, private/[types, utils, session]
export SSHException, AuthenticationException, FileNotFoundException

export SftpAttributes

proc initSFTPClient*(ssh: SSHClient): SFTPClient =
  ## Init new SCPClient instance from a SSHClient
  result.session = ssh.session
  result.socket = ssh.socket

  while true:
    result.sftp_session = sftp_init(ssh.session)
    if result.sftp_session == nil and ssh.session.session_last_errno() == LIBSSH2_ERROR_EAGAIN:
      discard ssh.waitsocket()
    else:
      break
  if result.sftp_session == nil:
    raise newException(SSHException, ssh.session.getLastErrorMessage())

proc close*(client: var SFTPClient) =
  discard client.sftp_session.sftp_shutdown()
  client.sftp_session = nil

proc put*(client: SFTPClient, localPath, remotePath: string) {.async.} =
  var
    handle: SftpHandle
    buffer: array[1024, char]
    bytesRead: int
    bytesWrite: cint
    f: File

  if not localPath.fileExists():
    raise newException(FileNotFoundException, &"{localPath}: No such file or directory")

  while true:
    handle = client.sftp_session.sftp_open(remotePath, LIBSSH2_FXF_WRITE or LIBSSH2_FXF_CREAT or LIBSSH2_FXF_TRUNC, LIBSSH2_SFTP_S_IRUSR or LIBSSH2_SFTP_S_IWUSR or LIBSSH2_SFTP_S_IRGRP or LIBSSH2_SFTP_S_IROTH)
    if handle != nil: break
    elif client.session.session_last_errno() != LIBSSH2_ERROR_EAGAIN:
      let errmsg = client.session.getLastErrorMessage()
      discard client.sftp_session.sftp_shutdown()
      raise newException(SSHException, &"sftp: {remotePath}: {errmsg}")
  f = open(localPath, fmRead)
  defer: f.close()
  while true:
    bytesRead = f.readBuffer(addr buffer, buffer.len)
    if bytesRead <= 0: break
    while true:
      bytesWrite = handle.sftp_write(addr buffer, bytesRead)
      if bytesWrite == LIBSSH2_ERROR_EAGAIN:
        discard waitsocket(client.session, client.socket)
      else:
        break
    if bytesWrite != bytesRead:
      raise newException(SSHException, &"sftp: fail to write data: {bytesWrite} wrote, {bytesRead} expected")
  discard handle.sftp_close()

proc get*(client: SFTPClient, remotePath, localPath: string) {.async.} =
  var
    handle: SftpHandle
    buffer: array[1024, char]
    bytesRead: int
    f: File
  while true:
    handle = client.sftp_session.sftp_open(remotePath, LIBSSH2_FXF_READ, 0)
    if handle != nil: break
    elif client.session.session_last_errno() == LIBSSH2_ERROR_EAGAIN:
      discard waitsocket(client.session, client.socket)
    else:
      let errmsg = client.session.getLastErrorMessage()
      discard handle.sftp_close()
      discard client.sftp_session.sftp_shutdown()
      raise newException(SSHException, &"sftp: {remotePath}: {errmsg}")

  f = open(localPath, fmWrite)
  defer: f.close()

  while true:
    let rc = handle.sftp_read(addr buffer, buffer.len)
    if rc > 0:
      let bytesWrite = f.writeBuffer(addr buffer, rc)
      if bytesWrite != rc:
        raise newException(SSHException, &"sftp: fail to write data: {bytesWrite} wrote, {rc} expected")
      inc(bytesRead, rc)
    elif rc == LIBSSH2_ERROR_EAGAIN:
      discard waitsocket(client.session, client.socket)
    else:
      break
  discard handle.sftp_close()

proc mkdir*(client: SFTPClient, path: string, mode: int32 = 0) =
  ## create a directory on the remote file system
  var mode = mode
  if mode == 0:
    mode = LIBSSH2_SFTP_S_IRWXU or LIBSSH2_SFTP_S_IRGRP or LIBSSH2_SFTP_S_IXGRP or LIBSSH2_SFTP_S_IROTH or LIBSSH2_SFTP_S_IXOTH

  wait(client.sftp_session.sftp_mkdir(path, mode))

proc rmdir*(client: SFTPClient, path: string) =
  ## remove an SFTP directory
  wait(client.sftp_session.sftp_rmdir(path))

proc unlink*(client: SFTPClient, path: string) =
  ## unlink an SFTP file
  wait(client.sftp_session.sftp_unlink(path))

proc rename*(client: SFTPClient, sourcefile, destfile: string) {.async.} =
  ## rename an SFTP file
  wait(client.sftp_session.sftp_rename(sourcefile, destfile))

iterator items*(client: SFTPClient, path: string): tuple[name: string, attributes: SftpAttributes] =
  var
    handle: SftpHandle
    rc: cint
  while true:
    handle = client.sftp_session.sftp_opendir(path)
    if handle != nil: break
    elif client.session.session_last_errno() == LIBSSH2_ERROR_EAGAIN:
      discard waitsocket(client.session, client.socket)
    else:
      let errmsg = client.session.getLastErrorMessage()
      discard handle.sftp_close()
      discard client.sftp_session.sftp_shutdown()
      raise newException(SSHException, &"sftp: {path}: {errmsg}")

  while true:
    var
      name: array[512, char]
      attrs: SftpAttributes
    while true:
      rc = handle.sftp_readdir(addr name, name.len, addr attrs)
      if rc != LIBSSH2_ERROR_EAGAIN:
        break
    if rc > 0:
      yield ($cast[cstring](addr name), attrs)
    elif rc == LIBSSH2_ERROR_EAGAIN:
      discard
    else:
      break

proc dir*(client: SFTPClient, path: string): Future[seq[tuple[name: string, attributes: SftpAttributes]]] {.async.} =

  result = @[]
  for item in client.items(path):
    result.add(item)
