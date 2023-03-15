import libssh2, types, asyncnet

when defined(windows):
  import winlean
else:
  import posix

proc waitsocket*(session: Session, socket: AsyncSocket): int =
  var
    timeout: Timeval
    fd: TFdSet
    writefd: TFdSet
    readfd: TFdSet
    dir: int

  timeout.tv_sec = 10
  timeout.tv_usec = 0

  FD_ZERO(fd)
  FD_SET(socket.getFd(), fd)

  dir = session.sessionBlockDirections()

  if((dir and LIBSSH2_SESSION_BLOCK_INBOUND) == LIBSSH2_SESSION_BLOCK_INBOUND):
    readfd = fd

  if((dir and LIBSSH2_SESSION_BLOCK_OUTBOUND) == LIBSSH2_SESSION_BLOCK_OUTBOUND):
    writefd = fd

  var sfd  = cast[cint](socket) + 1

  result = select(sfd, addr readfd, addr writefd, nil, addr timeout);

proc waitsocket*(s: SSHClient): int {.inline.} = waitsocket(s.session, s.socket)

template wait*(body: untyped) =
  while body != LIBSSH2_ERROR_EAGAIN: break

proc `|`*[T](a, b: T): T = cast[T](a or b)