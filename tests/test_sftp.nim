import asyncdispatch, ssh2, ssh2/sftp

proc main() {.async.} =
  var client = newSSHClient()
  defer: client.disconnect()
  await client.connect("127.0.0.1", "nim", Port(2222), password="secret")
  var sftp = client.initSFTPClient()
  echo await client.execCommand("ls /tmp")
  await sftp.mkdir("/tmp/DIR1")
  echo await client.execCommand("ls /tmp")
  await sftp.rmdir("/tmp/DIR1")
  echo await client.execCommand("ls /tmp")
  await sftp.put("LICENSE", "/tmp/LICENSE")
  await sftp.get("/tmp/LICENSE", "TEST")
  sftp.close()

waitFor main()