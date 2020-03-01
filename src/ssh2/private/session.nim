import libssh2, types, strformat, posix

proc initSession*(): Session =
  result = session_init()

proc setBlocking*(session: Session, blocking: bool) {.inline.} =
  session.session_set_blocking(blocking.cint)

proc handshake*(session: Session, fd: SocketHandle) {.inline.} =
  var rc: cint
  while true:
    rc = session.session_handshake(fd)
    if rc  != LIBSSH2_ERROR_EAGAIN:
      break
  if rc != 0:
    raise newException(SSHException, "Failure establing ssh connection")

proc authPassword*(session: Session, username, password: string): bool =
  while true:
    let rc = session.userauth_password(username, password, nil)
    if rc == LIBSSH2_ERROR_EAGAIN:
      discard
    elif rc < 0:
      raise newException(AuthenticationException, &"Authentication with username {username} and password failed!")
    else:
      break
  result = true

proc getLastError*(session: Session): (string, int) =
  var
    errmsg: cstring
    errlen: cint
  let errcode = session.session_last_error(addr errmsg, addr errlen, 0)
  result = ($errmsg, errcode.int)

proc getLastErrorMessage*(session: Session): string =
  let (msg, code) = getLastError(session)
  result = &"{msg} ({code})"

proc close*(session: Session) =
  while session.session_disconnect("libssh2 wrapper for Nim, libssh2.nim/core") == LIBSSH2_ERROR_EAGAIN:
    discard
  discard session.session_free()