import asyncdispatch, ssh2, ssh2/scp

proc main() {.async.} =
  var client = newSSHClient()
  defer: client.disconnect()
  await client.connect("10.8.11.12", "root", useAgent=true)
  #echo await client.execCommand("/tmp/test.sh &")
  #echo await client.execCommand("rm /tmp/LICENSE")
  #echo await client.execCommand("ls /tmp")
  let scp = client.initSCPClient()
  #await scp.uploadFile("LICENSE", "/tmp/LICENSE")
  await scp.downloadFile("/tmp/LICENSE", "TEST")
  echo await client.execCommand("ls /tmp")
  #echo await client.execCommand("uptime")


waitFor main()