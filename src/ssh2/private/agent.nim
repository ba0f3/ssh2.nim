import libssh2, types, strformat

proc initAgent*(session: Session): Agent {.inline.} =
  result = session.agent_init()
  if result.isNil:
    raise newException(SSHException, "Failure initializing ssh-agent support")

proc connect*(agent: Agent) {.inline.} =
  if agent.agent_connect() < 0:
    raise newException(SSHException, "Failure connecting to ssh-agent")

proc listIdentities*(agent: Agent) {.inline.} =
  if agent.agent_list_identities() < 0:
    raise newException(SSHException, "Failure requesting identities to ssh-agent")

iterator identities*(agent: Agent): AgentPublicKey =
  var
    identity: AgentPublicKey
    prevIdentity: AgentPublicKey

  while true:
    var rc = agent.agent_get_identity(addr identity, prevIdentity)
    if rc == 1:
      break
    elif rc < 0:
      raise newException(SSHException, "Failure obtaining identity from ssh-agent support")
    else:
      yield identity
    prevIdentity = identity

proc authenticate*(agent: Agent, identity: AgentPublicKey, username: string): bool =
  var rc: cint
  while true:
    rc = agent.agent_userauth(username, identity)
    if rc != LIBSSH2_ERROR_EAGAIN:
      break
  if rc != 0:
    raise newException(AuthenticationException, &"Authentication with username {username} and public key {identity.comment} failed!")

  result = true

proc close*(agent: Agent) =
  discard agent.agent_disconnect()
  agent.agentFree()

proc close_agent*(agent: Agent) =
  close(agent)
