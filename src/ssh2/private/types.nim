import libssh2
from asyncnet import AsyncSocket

type
  SSHClient* = ref object of RootObj
    socket*: AsyncSocket
    session*: Session

  SCPClient* = object
    session*: Session
    socket*: AsyncSocket

  SFTPClient* = object
    session*: Session
    socket*: AsyncSocket
    sftp_session*: Sftp

  SSHChannel* = object
    impl*: Channel
    client*: SSHClient


  SSHException* = object of IOError
  AuthenticationException* = object of SSHException
  FileNotFoundException* = object of SSHException

