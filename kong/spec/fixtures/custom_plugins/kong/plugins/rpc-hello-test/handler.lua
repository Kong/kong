local RpcHelloTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


function RpcHelloTestHandler:init_worker()
  kong.rpc.callbacks:register("kong.test.hello", function(node_id, greeting)
    return "hello ".. greeting
  end)
end


function RpcHelloTestHandler:access()
  local greeting = kong.request.get_headers()["x-greeting"]
  if not greeting then
    kong.response.exit(400, "Greeting header is required")
  end

  local res, err = kong.rpc:call("control_plane", "kong.test.hello", greeting)
  if not res then
    return kong.response.exit(500, err)
  end

  return kong.response.exit(200, res)
end


return RpcHelloTestHandler
