local rep = string.rep
local isempty = require("table.isempty")


local RpcSyncV2NotifyNewVersioinTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


function RpcSyncV2NotifyNewVersioinTestHandler:init_worker()
  -- mock function on cp side
  kong.rpc.callbacks:register("kong.sync.v2.get_delta", function(node_id, current_versions)
    local latest_version = "v02_" .. string.rep("1", 28)

    local deltas = {}

    return { default = { deltas = deltas, wipe = true, }, }
  end)

  -- call dp's sync.v2.notify_new_version
  kong.rpc.callbacks:register("kong.test.notify_new_version", function(node_id)
  end)

  local worker_events = assert(kong.worker_events)

  -- if rpc is ready we will send test calls
  worker_events.register(function(capabilities_list)
    local node_id = "control_plane"

    local res, err = kong.rpc:call(node_id, "kong.test.notify_new_version")

    ngx.log(ngx.DEBUG, "kong.sync.v2.notify_new_version ok")

  end, "clustering:jsonrpc", "connected")
end


return RpcSyncV2NotifyNewVersioinTestHandler
