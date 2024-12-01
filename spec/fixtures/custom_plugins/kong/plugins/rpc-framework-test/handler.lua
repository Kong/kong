local RpcFrameworkTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


function RpcFrameworkTestHandler:init_worker()
  kong.rpc.callbacks:register("kong.test.hello", function(node_id, greeting)
    return "hello ".. greeting
  end)
end


return RpcFrameworkTestHandler
