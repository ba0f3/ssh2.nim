import asyncdispatch, ssh2, ssh2/sftp

proc main() {.async.} =
  var client = newSSHClient()
  defer: client.disconnect()
  await client.connect("127.0.0.1", "nim", Port(2222), password="secret")
  var sftp = client.initSFTPClient()
  sftp.mkdir("/tmp/DIR1")
  await sftp.put("LICENSE", "/tmp/LICENSE")
  echo await sftp.dir("/tmp")
  sftp.rmdir("/tmp/DIR1")
  await sftp.get("/tmp/LICENSE", "TEST")
  sftp.unlink("/tmp/LICENSE")


  sftp.close()
waitFor main()