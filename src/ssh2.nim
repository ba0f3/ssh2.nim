## SSH2 for Nim
## =============
##
## This module provides a high-level async API for SSH operations using libssh2.
## It supports SSH connections, command execution, and various authentication methods.
##
## Example
## -------
##
## ```nim
## import asyncdispatch
## import ssh2
##
## proc main() {.async.} =
##   let client = newSSHClient()
##   try:
##     # Connect with password authentication
##     await client.connect("example.com", "user", password = "pass")
##
##     # Execute a command
##     let (stdout, stderr, exitcode) = await client.execCommand("ls -la")
##     echo "Exit code: ", exitcode
##     echo "Output: ", stdout
##     if stderr.len > 0:
##       echo "Errors: ", stderr
##   finally:
##     client.disconnect()
##
## waitFor main()
## ```
##
## Authentication
## --------------
## The module supports multiple authentication methods:
## * Password authentication
## * Public key authentication
## * SSH agent authentication
##
## Error Handling
## --------------
## The module uses custom exceptions:
## * SSHException: General SSH errors
## * AuthenticationException: Authentication-related errors

import asyncdispatch, asyncnet, strformat
from libssh2 import init, free, exit
import ssh2/private/[agent, channel, types, session]
export SSHException, AuthenticationException

export agent, channel, types, session

proc newSSHClient*(): SSHClient =
  ## Creates a new SSH client and initializes the underlying libssh2 library.
  ## Raises SSHException if initialization fails.
  ##
  ## Returns:
  ##   A new SSHClient instance ready for connections
  if init(0) != 0:
    raise newException(SSHException, "libssh2 initialization failed")
  result = new SSHClient

proc disconnect*(ssh: SSHClient) =
  ## Cleanly disconnects the SSH session and frees resources.
  ## Should be called when the client is no longer needed.
  ##
  ## It's recommended to use this in a `finally` block or with defer:
  ## ```nim
  ## let client = newSSHClient()
  ## defer: client.disconnect()
  ## ```
  if ssh.session != nil:
    ssh.session.close_session()
    ssh.session = nil

  ssh.socket.close()
  libssh2.exit()

proc connect*(s: SSHClient, hostname: string, username: string, port = Port(22), password = "", privKey = "", pubKey = "", useAgent = false) {.async.} =
  ## Establishes an SSH connection to a remote host with the specified authentication method.
  ##
  ## Parameters:
  ##   hostname: The remote host to connect to
  ##   username: The username for authentication
  ##   port: The SSH port (default: 22)
  ##   password: Optional password for password auth or private key passphrase
  ##   privKey: Path to private key file for public key authentication
  ##   pubKey: Path to public key file (optional with private key)
  ##   useAgent: Whether to attempt authentication using SSH agent
  ##
  ## Authentication Methods:
  ## * Password: Set `password` parameter
  ## * Public Key: Set `privKey` and optionally `pubKey`
  ## * SSH Agent: Set `useAgent` to true
  ##
  ## Raises:
  ##   SSHException: On connection or handshake failure
  ##   AuthenticationException: On authentication failure
  s.socket = newAsyncSocket()
  s.socket.setSockOpt(OptNoDelay, true, level = 6)
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
  ## Executes a command on the remote host and returns its output.
  ##
  ## Parameters:
  ##   command: The shell command to execute
  ##
  ## Returns:
  ##   A tuple containing:
  ##   * stdout (string): Standard output from the command
  ##   * stderr (string): Standard error from the command
  ##   * exitcode (int): Exit code of the command
  ##
  ## Raises:
  ##   SSHException: If command execution fails
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
