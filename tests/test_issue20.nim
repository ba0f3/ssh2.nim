import std/asyncdispatch, std/strutils
import std/asyncnet
import std/nativesockets
import pkg/ssh2

proc main() {.async.} =
  var client = newSSHClient()
  defer: client.disconnect()
  await client.connect("127.0.0.1", "root", Port(2222), password="root")
  #client.socket.setSockOpt(OptNoDelay, true, level = IPPROTO_TCP.cint)  # uncomment to make it fast
  let x = await client.execCommand("date +\"%T.%N\"")
  echo x
  let y = await client.execCommand("date +\"%T.%N\"")
  echo y

proc main2 =
  let fut = main()
  while not fut.finished:
    poll()
  fut.read
main2()