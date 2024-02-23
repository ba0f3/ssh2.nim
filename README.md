# ssh2.nim
High level async SSH, SCP and SFTP client for Nim, using libssh2 wrapper

## Usage
```nim
import asyncdispatch, ssh2, ssh2/scp

proc main() {.async.} =
  var client = newSSHClient()
  defer: client.disconnect()
  await client.connect("127.0.0.1", "root", Port(2222), password="root")
  echo await client.execCommand("uptime")

waitFor main()
```

### Development
In order to run tests, you can use a Docker instance with sshd installed.

For example:

```
# Host: 127.0.0.1
# Port: 2222
# Username: root
# Password: root

docker run -d --name test_sshd -p 2222:22 rastasheep/ubuntu-sshd:16.04
```