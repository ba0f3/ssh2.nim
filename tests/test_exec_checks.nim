import asyncdispatch, ssh2, ssh2/scp
import terminal

proc main() {.async.} =
  var client = newSSHClient()
  defer: client.disconnect()
  write stdout, "User: "
  let user = readLine(stdin)
  write stdout, "Host: "
  let host = readLine(stdin)
  let passwd = readPasswordFromStdin("Password: ")
  try:
    await client.connect(host, user, Port(22), password=passwd)
  except OSError as e:
    echo "Connection establishment error: ", e.msg
    quit(1)
  except AuthenticationException as e:
    echo "Authentication error: ", e.msg
    quit(1)
  echo await client.execCommand("uptime")

waitFor main()
