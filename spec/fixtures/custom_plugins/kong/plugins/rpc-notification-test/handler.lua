local RpcNotificationTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


function RpcNotificationTestHandler:init_worker()
  kong.rpc.callbacks:register("kong.test.notification", function(node_id, msg)
    ngx.log(ngx.DEBUG, "notification is ", msg)

    -- called by cp
    if kong.configuration.role == "data_plane" then
      return "data_plane"
    end

    -- cp notify dp back
    local res, err = kong.rpc:notify(node_id, "kong.test.notification", "world")
    assert(res == true)
    assert(err == nil)

    return "control_plane"
  end)
end


function RpcNotificationTestHandler:access()
  -- dp notify cp
  local res, err = kong.rpc:notify("control_plane", "kong.test.notification", "hello")

  assert(res == true)
  assert(err == nil)
end


return RpcNotificationTestHandler
