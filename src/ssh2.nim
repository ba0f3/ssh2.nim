import asyncdispatch, asyncnet, strformat
from libssh2 import init, free, exit
import ssh2/private/[agent, channel, types, session]
export SSHException, AuthenticationException

export agent, channel, types, session

proc newSSHClient*(): SSHClient =
  if init(0) != 0:
    raise newException(SSHException, "libssh2 initialization failed")
  result = new SSHClient

proc disconnect*(ssh: SSHClient) =
  if ssh.session != nil:
    ssh.session.close_session()
    ssh.session = nil

  ssh.socket.close()
  libssh2.exit()

proc connect*(s: SSHClient, hostname: string, username: string, port = Port(22), password = "", privKey = "", pubKey = "", useAgent = false) {.async.} =
  s.socket = newAsyncSocket()
  await s.socket.connect(hostname, port)
  s.session = initSession()
  s.session.setBlocking(false)
  s.session.handshake(s.socket.getFd())

  if useAgent:
    let agent = initAgent(s.session)
    agent.connect()
    agent.listIdentities()

    for identity in agent.identities:
      if agent.authenticate(identity, username):
        break
    agent.close_agent()
  else:
    if privKey.len != 0:
      discard s.session.authPublicKey(username, privKey, pubKey, password)
    else:
      discard s.session.authPassword(username, password)

proc execCommand*(s: SSHClient, command: string): Future[(string, string, int)] {.async.} =
  var channel = initChannel(s)
  if not channel.exec(command):
    raise newException(SSHException, &"Error: {s.session.getLastErrorMessage()}")

  var
    stdout: string
    stderr: string
    exitcode = 127

  stdout = channel.read()
  stderr = channel.read_error()

  if channel.close():
    exitcode = channel.get_exit_status()
  channel.free()
  result = (stdout, stderr, exitcode)
