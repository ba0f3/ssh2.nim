import asyncdispatch, ssh2, ssh2/scp

proc main() {.async.} =
  var client = newSSHClient()
  defer: client.disconnect()
  await client.connect("127.0.0.1", "root", Port(2222), password="root")
  let scp = client.initSCPClient()
  await scp.uploadFile("LICENSE", "/tmp/LICENSE")
  await scp.downloadFile("/tmp/LICENSE", "TEST")

waitFor main()