local RpcBatchTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


function RpcBatchTestHandler:init_worker()
  kong.rpc.callbacks:register("kong.test.batch", function(node_id, greeting)
    ngx.log(ngx.DEBUG, "kong.test.batch called: ", greeting)
    return "hello ".. greeting
  end)
end


function RpcBatchTestHandler:access()
  kong.rpc:set_batch(1)

  local res, err = kong.rpc:call("control_plane", "kong.test.batch", "world")
  if not res then
    return kong.response.exit(500, err)
  end

  ngx.log(ngx.DEBUG, "kong.test.batch called: ", res)

  kong.rpc:set_batch(2)
  kong.rpc:notify("control_plane", "kong.test.batch", "kong")
  kong.rpc:notify("control_plane", "kong.test.batch", "gateway")

  return kong.response.exit(200, res)
end


return RpcBatchTestHandler
