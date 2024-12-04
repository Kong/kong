local RpcNotificationTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


function RpcNotificationTestHandler:init_worker()
  kong.rpc.callbacks:register("kong.test.notification", function(node_id, msg)
    ngx.log(ngx.DEBUG, "notification is ", msg)

    local role = kong.configuration.role

    -- cp notify dp back
    if role == "control_plane" then
      local res, err = kong.rpc:notify(node_id, "kong.test.notification", "world")
      assert(res == true)
      assert(err == nil)
    end

    -- perr should not get this by notification
    return role
  end)
end


function RpcNotificationTestHandler:rewrite()
  -- dp notify cp
  local res, err = kong.rpc:notify("control_plane", "kong.test.notification", "hello")

  assert(res == true)
  assert(err == nil)
end


return RpcNotificationTestHandler
