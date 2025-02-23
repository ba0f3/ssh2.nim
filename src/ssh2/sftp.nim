## SFTP (SSH File Transfer Protocol) Implementation
## =============================================
##
## This module provides SFTP functionality for secure file operations over SSH.
## It supports file transfers, directory operations, and file system manipulation.
##
## Example
## -------
##
## ```nim
## import asyncdispatch
## import ssh2
## import ssh2/sftp
##
## proc main() {.async.} =
##   let ssh = newSSHClient()
##   try:
##     await ssh.connect("example.com", "user", password = "pass")
##     var sftp = initSFTPClient(ssh)
##     defer: sftp.close()
##
##     # Create a directory
##     sftp.mkdir("/remote/new_dir")
##
##     # Upload a file
##     await sftp.put("local.txt", "/remote/new_dir/file.txt")
##
##     # Download a file
##     await sftp.get("/remote/new_dir/file.txt", "local_copy.txt")
##
##     # List directory contents
##     let files = await sftp.dir("/remote/new_dir")
##     for file in files:
##       echo "Name: ", file.name
##       echo "Size: ", file.attributes.filesize
##   finally:
##     ssh.disconnect()
##
## waitFor main()
## ```
##

import asyncdispatch, strformat, os, posix, posix_utils
import libssh2, private/[types, utils, session]

export SftpAttributes

proc initSFTPClient*(ssh: SSHClient): SFTPClient =
  ## Creates a new SFTP client from an existing SSH connection.
  ##
  ## Parameters:
  ##   ssh: An authenticated SSHClient instance
  ##
  ## Returns:
  ##   A new SFTPClient instance ready for file operations
  ##
  ## Raises:
  ##   SSHException: If SFTP session initialization fails
  ##
  ## Note: The SSH connection must be established before creating an SFTP client.
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
  ## Closes the SFTP session and frees associated resources.
  ##
  ## Parameters:
  ##   client: The SFTP client to close
  ##
  ## Note: Always close the SFTP session when done to free resources.
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
  ## Downloads a file from the remote server to the local system using SFTP.
  ##
  ## Parameters:
  ##   remotePath: Path to the file on the remote server
  ##   localPath: Destination path on the local system where the file will be saved
  ##
  ## The procedure will:
  ## * Open the remote file in read mode
  ## * Create or overwrite the local file
  ## * Transfer the file contents in blocks
  ## * Automatically handle large files by using buffered transfer
  ##
  ## Raises:
  ##   SSHException: If the remote file doesn't exist or is not accessible
  ##   SSHException: If there are permission issues
  ##   SSHException: If the transfer fails or is interrupted
  ##   IOError: If the local file cannot be created or written to
  ##
  ## Example:
  ##   ```nim
  ##   let sftp = initSFTPClient(ssh)
  ##   try:
  ##     await sftp.get("/remote/data.txt", "local_data.txt")
  ##     echo "File downloaded successfully"
  ##   except SSHException as e:
  ##     echo "Download failed: ", e.msg
  ##   ```
  ##
  ## Note: The procedure uses a block size of 1024 bytes for efficient
  ## transfer and memory usage. The transfer is done asynchronously
  ## to prevent blocking the main thread.
  const blockSize = 1024
  var
    handle: SftpHandle
    s: cstring
    buffer: array[blockSize, char]
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
    s = cast[cstring](create(char, blockSize + 1))
    moveMem(addr s, addr buffer, blockSize)
    let rc = handle.sftp_read(addr s, blockSize)
    if rc > 0:
      let bytesWrite = f.writeBuffer(addr s, rc)
      if bytesWrite != rc:
        raise newException(SSHException, &"sftp: fail to write data: {bytesWrite} wrote, {rc} expected")
      inc(bytesRead, rc)
    elif rc == LIBSSH2_ERROR_EAGAIN:
      discard waitsocket(client.session, client.socket)
    else:
      break
  discard handle.sftp_close()

proc mkdir*(client: SFTPClient, path: string, mode: uint64 = 0) =
  ## Creates a directory on the remote file system.
  ##
  ## Parameters:
  ##   path: Path where to create the directory
  ##   mode: Unix-style permission mode (default: rwxr-xr-x)
  ##
  ## Note: If mode is 0, default permissions (0755) will be used
  var mode = mode
  if mode == 0:
    mode = LIBSSH2_SFTP_S_IRWXU or LIBSSH2_SFTP_S_IRGRP or LIBSSH2_SFTP_S_IXGRP or LIBSSH2_SFTP_S_IROTH or LIBSSH2_SFTP_S_IXOTH

  wait(client.sftp_session.sftp_mkdir(path, mode))

proc rmdir*(client: SFTPClient, path: string) =
  ## Removes a directory from the remote file system.
  ##
  ## Parameters:
  ##   path: Path to the directory to remove
  ##
  ## Note: Directory must be empty to be removed
  wait(client.sftp_session.sftp_rmdir(path))

proc unlink*(client: SFTPClient, path: string) =
  ## Removes a file from the remote file system.
  ##
  ## Parameters:
  ##   path: Path to the file to remove
  wait(client.sftp_session.sftp_unlink(path))

proc rename*(client: SFTPClient, sourcefile, destfile: string) {.async.} =
  ## Renames or moves a file on the remote file system.
  ##
  ## Parameters:
  ##   sourcefile: Current path of the file
  ##   destfile: New path for the file
  wait(client.sftp_session.sftp_rename(sourcefile, destfile))

iterator items*(client: SFTPClient, path: string): tuple[name: string, attributes: SftpAttributes] =
  ## Iterates over the contents of a remote directory.
  ##
  ## Parameters:
  ##   path: Path to the directory to list
  ##
  ## Returns:
  ##   Iterator yielding tuples containing file names and their attributes
  ##
  ## Example:
  ##   ```nim
  ##   for item in sftp.items("/remote/dir"):
  ##     echo "File: ", item.name
  ##     echo "Size: ", item.attributes.filesize
  ##   ```
  var
    handle: SftpHandle
    rc: cint
  while true:
    handle = client.sftp_session.sftp_opendir(path, flags = 0, mode = 0)
    if handle != nil: break
    elif client.session.session_last_errno() == LIBSSH2_ERROR_EAGAIN:
      discard waitsocket(client.session, client.socket)
    else:
      let errmsg = client.session.getLastErrorMessage()
      discard handle.sftp_close()
      discard client.sftp_session.sftp_shutdown()
      raise newException(SSHException, &"sftp: {path}: {errmsg}")

  while true:
    const blockSize = 512
    var
      s: cstring
      name: array[blockSize, char]
      attrs: SftpAttributes
    while true:
      s = cast[cstring](create(char, blockSize + 1))
      moveMem(addr s, addr name, blockSize)
      rc = handle.sftp_readdir(addr s, blockSize, addr attrs)
      if rc != LIBSSH2_ERROR_EAGAIN:
        break
    if rc > 0:
      yield ($cast[cstring](addr s), attrs)
    elif rc == LIBSSH2_ERROR_EAGAIN:
      discard
    else:
      break

proc dir*(client: SFTPClient, path: string): Future[seq[tuple[name: string, attributes: SftpAttributes]]] {.async.} =
  ## Lists the contents of a remote directory asynchronously.
  ##
  ## Parameters:
  ##   path: Path to the directory to list
  ##
  ## Returns:
  ##   Sequence of tuples containing file names and their attributes
  ##
  ## Example:
  ##   ```nim
  ##   let files = await sftp.dir("/remote/dir")
  ##   for file in files:
  ##     echo "Name: ", file.name
  ##     echo "Size: ", file.attributes.filesize
  ##   ```
  for item in client.items(path):
    result.add(item)
