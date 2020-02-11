import ../libssh2 except Channel
import types

proc openSession*(session: Session): Channel =
  ## Establish a generic session channel
  result.impl = session.channelOpenSession()
  if result.impl == nil:
    raise newException(SSHException, session.getErrorMessage())

proc setEnv*(channel: Channel, name, value: string) =
  ## Set an environment variable on the channel
  let rc = channel.impl.channelSetEnv(name, value)
  if rc == -1:
    raise newException(SSHException, session.getErrorMessage())

proc requestPty(channel: Channel, terminalType: string)