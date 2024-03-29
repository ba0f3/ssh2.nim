import libssh2, types, session, utils, streams

proc initChannel*(ssh: SSHClient): SSHChannel =
  ## Establish a generic session channel
  result.client = ssh
  while true:
    result.impl = ssh.session.channel_open_session()
    if result.impl == nil and ssh.session.session_last_errno() == LIBSSH2_ERROR_EAGAIN:
      discard ssh.waitsocket()
    else:
      break
  if result.impl == nil:
    raise newException(SSHException, ssh.session.getLastErrorMessage())

proc setEnv*(channel: SSHChannel, name, value: string): bool {.inline.} =
  ## Set an environment variable on the channel
  return channel.impl.channel_set_env(name, value) != -1

proc exec*(channel: SSHChannel, command: string): bool =
  var rc: cint
  while true:
    rc = channel.impl.channel_exec(command)
    if rc != LIBSSH2_ERROR_EAGAIN:
      break
  return rc == 0

proc read*(channel: SSHChannel): string =
  var
    buffer: array[0..1024, char]
    rc: cint
    stream = newStringStream()

  while true:
    rc = channel.impl.channel_read(addr buffer, buffer.len)
    if rc > 0:
      stream.writeData(addr buffer, rc)
    elif rc == LIBSSH2_ERROR_EAGAIN:
      discard waitsocket(channel.client)
    else:
      break
  stream.setPosition(0)
  result = stream.readAll()

proc readError*(channel: SSHChannel): string =
  var
    buffer: array[0..1024, char]
    rc: cint
    stream = newStringStream()

  while true:
    rc = channel.impl.channel_read_stderr(addr buffer, buffer.len)
    if rc > 0:
      stream.writeData(addr buffer, rc)
    elif rc == LIBSSH2_ERROR_EAGAIN:
      discard waitsocket(channel.client)
    else:
      break
  stream.setPosition(0)
  result = stream.readAll()

proc close*(channel: SSHChannel): bool =
  var rc: cint
  while true:
    rc = channel.impl.channel_close()
    if rc == LIBSSH2_ERROR_EAGAIN:
      discard waitsocket(channel.client)
    else:
      break
  return rc == 0

proc getExitStatus*(channel: SSHChannel): int {.inline.} =
  channel.impl.channel_get_exit_status()

#proc getExitSignal*(channel: SSHChannel): int {.inline.} =
#  channel.impl.channel_get_exit_signal()

proc free*(channel: SSHChannel) =
  discard channel.impl.channel_free()
