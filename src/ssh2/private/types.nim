import libssh2
from asyncnet import AsyncSocket

type
  SSHClient* = ref object of RootObj
    socket*: AsyncSocket
    session*: Session
    agent*: Agent

  SCPClient* = object
    session*: Session
    socket*: AsyncSocket

  #Channel* = object
  #  impl*: libssh2.Channel

  SSHException* = object of IOError
  AuthenticationException* = object of SSHException
  FileNotFoundException* = object of SSHException

