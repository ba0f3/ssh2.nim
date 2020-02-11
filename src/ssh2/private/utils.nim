import libssh2, types, posix, asyncnet

proc waitsocket*(session: Session, socket: AsyncSocket): int =
  var
    timeout: Timeval
    fd: TFdSet
    writefd: TFdSet
    readfd: TFdSet
    dir: int

  timeout.tv_sec = 10.Time
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

template ensure*(body: untyped) =
  while body == LIBSSH2_ERROR_EAGAIN: discard