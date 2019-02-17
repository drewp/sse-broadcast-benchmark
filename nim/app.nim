import asynchttpserver, asyncdispatch, asyncnet, strtabs, sequtils, times, os, strutils

var previousUpdateTime = toInt(epochTime() * 1000)

proc handleCORS(req: Request) {.async.} =
  await req.respond(Http204, "", newHttpHeaders({
    "Access-Control-Allow-Origin": "*",
    "Connection": "close"}))

proc handleConnections(req: Request, clients: ref seq[AsyncSocket]) {.async.} =
  let clientCount = clients[].len
  let headers = newHttpHeaders({"Content-Type": "text/plain",
                                 "Access-Control-Allow-Origin": "*",
                                 "Cache-Control": "no-cache",
                                 "Connection": "close"})

  await req.respond(Http200, $clientCount, headers)
  req.client.close()

proc handle404(req: Request) {.async.} =
  let headers = newHttpHeaders({"Content-Type": "text/plain",
                                 "Connection": "close"})

  await req.respond(Http404, "File not found", headers)
  req.client.close()

proc handleSSE(req: Request, clients: ref seq[AsyncSocket]) {.async.} =
  let headers = newHttpHeaders({"Content-Type": "text/event-stream",
                                 "Access-Control-Allow-Origin": "*",
                                 "Cache-Control": "no-cache",
                                 "Connection": "keep-alive"})

  await req.client.send("HTTP/1.1 200 OK\c\L")
  await req.sendHeaders(headers)
  await req.client.send("\c\L:ok\n\n")
  clients[].add(req.client)

proc requestCallback(req: Request, clients: ref seq[AsyncSocket]) {.async.} =
  if req.reqMethod == HttpOptions:
    asyncCheck handleCORS(req)
  else:
    case req.url.path
    of "/connections": asyncCheck handleConnections(req, clients)
    of "/sse": asyncCheck handleSSE(req, clients)
    else: asyncCheck handle404(req)

proc pingClients(clients: ref seq[AsyncSocket]) {.async.} =
  let currentTime = toInt(epochTime() * 1000)

  if currentTime - previousUpdateTime < 1000: return

  for client in clients[]:
    if not client.isClosed():
      asyncCheck client.send("data: " & $currentTime & "\n\n")

  previousUpdateTime = toInt(epochTime() * 1000)


proc main(port = 1942) =
  var clients: ref seq[AsyncSocket]
  new clients

  proc checkClients() =
    clients[] = clients[].filterIt(not it.isClosed())

  let httpServer = newAsyncHttpServer(true)

  asyncCheck httpServer.serve(
    Port(port),
    proc (req: Request): Future[void] = requestCallback(req, clients))

  echo "Listening on http://127.0.0.1:" & $port

  while true:
    checkClients()
    asyncCheck pingClients(clients)
    poll()

when isMainModule:
  main()
