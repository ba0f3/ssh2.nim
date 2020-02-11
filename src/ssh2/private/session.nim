import libssh2, strformat

proc initSession*(): Session =
  result = sessionInit()

proc getLastError*(session: Session): (string, int) =
  var
    errmsg: cstring
    errlen: int
  let errcode = session.sessionLastError(addr errmsg, errlen, 0)
  result = ($errmsg, errcode.int)

proc getLastErrorMessage*(session: Session): string =
  let (msg, code) = getLastError(session)
  result = &"{msg} ({code})"