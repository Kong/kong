local RpcFrameworkTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


function RpcFrameworkTestHandler:init_worker()
  kong.rpc.callbacks:register("kong.test.hello", function(node_id, greeting)
    return "hello ".. greeting
  end)

  -- wait 0.2s for rpc established
  --[[
  ngx.timer.at(0.2, function()
    local res, err = kong.rpc:call("kong.test.hello", "world")
    ngx.log(ngx.ERR, "xxx res = ", res)
    ngx.log(ngx.ERR, "xxx err = ", err)
    --assert(res and not err)
    --assert(res == "hello world")
  end)
  --]]
end


return RpcFrameworkTestHandler
