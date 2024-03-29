import asyncdispatch, ssh2, ssh2/scp

proc main() {.async.} =
  var client = newSSHClient()
  defer: client.disconnect()
  await client.connect("127.0.0.1", "nim", Port(22), privKey="~/.ssh/id_rsa", password="secret")
  echo await client.execCommand("uptime")

waitFor main()
