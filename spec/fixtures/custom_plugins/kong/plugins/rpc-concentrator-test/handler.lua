local RpcConcentratorTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


function RpcConcentratorTestHandler:init_worker()
  local role = kong.configuration.role
  local prefix = string.sub(kong.configuration.prefix, -3)

  -- cp2 will invoke rpc call via concentrator
  if role == "control_plane" and prefix == "cp2" then
    -- wait 0.1s to ensure rpc is ready
    ngx.timer.at(0.1, function(premature)
      local res, err = kong.db.clustering_data_planes:page(64)
      assert(res and res[1] and not err)

      local node_id = assert(res[1].id)
      ngx.log(ngx.DEBUG, "[kong.test.concentrator] node_id: ", node_id)

      local res, err = kong.rpc:call(node_id, "kong.test.concentrator", "hello")
      assert(res and not err)
      assert(res == "got: hello")
    end)
  end

  kong.rpc.callbacks:register("kong.test.concentrator", function(node_id, msg)
    ngx.log(ngx.DEBUG, "kong.test.concentrator: ", msg)

    return "got: " .. msg
  end)

  local worker_events = assert(kong.worker_events)

  -- if rpc is ready we will write a log
  worker_events.register(function(capabilities_list)
    ngx.log(ngx.DEBUG, "[kong.test.concentrator] rpc framework is ready.")
  end, "clustering:jsonrpc", "connected")
end


return RpcConcentratorTestHandler
