local RpcHelloTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


function RpcHelloTestHandler:init_worker()
  kong.rpc.callbacks:register("kong.test.hello", function(node_id, greeting)
    return "hello ".. greeting
  end)
end


return RpcHelloTestHandler
