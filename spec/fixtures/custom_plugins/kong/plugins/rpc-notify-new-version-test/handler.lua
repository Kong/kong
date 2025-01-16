local fmt = string.format


local RpcSyncV2NotifyNewVersioinTestHandler = {
  VERSION = "1.0",
  PRIORITY = 1000,
}


function RpcSyncV2NotifyNewVersioinTestHandler:init_worker()
  -- mock function on cp side
  local counter = 0

  kong.rpc.callbacks:register("kong.sync.v2.get_delta", function(node_id, current_versions)
    local latest_version = fmt("v02_%028d", 10)

    local fake_uuid = "00000000-0000-0000-0000-111111111111"

    -- a basic config data
    local deltas = {
      {
        entity = {
          id = fake_uuid,
          name = "default",
        },
        type = "workspaces",
        version = latest_version,
        ws_id = fake_uuid,
      },
    }

    counter = counter + 1
    ngx.log(ngx.DEBUG, "kong.sync.v2.get_delta ok: ", counter)

    return { default = { deltas = deltas, wipe = true, }, }
  end)

  -- test dp's sync.v2.notify_new_version
  kong.rpc.callbacks:register("kong.test.notify_new_version", function(node_id)

    local dp_node_id = next(kong.rpc.clients)
    local method = "kong.sync.v2.notify_new_version"

    -- no default
    local msg = {}
    local res, err = kong.rpc:call(dp_node_id, method, msg)
    assert(not res)
    assert(err == "default namespace does not exist inside params")

    -- no default.new_version
    local msg = { default = {}, }
    local res, err = kong.rpc:call(dp_node_id, method, msg)
    assert(not res)
    assert(err == "'new_version' key does not exist")

    -- same version number
    local msg = { default = { new_version = fmt("v02_%028d", 10), }, }
    local res, err = kong.rpc:call(dp_node_id, method, msg)
    assert(res)
    assert(not err)

    -- less version number
    local msg = { default = { new_version = fmt("v02_%028d", 5), }, }
    local res, err = kong.rpc:call(dp_node_id, method, msg)
    assert(res)
    assert(not err)

    ngx.log(ngx.DEBUG, "kong.test.notify_new_version ok")

    return true
  end)

  local worker_events = assert(kong.worker_events)

  -- if rpc is ready we will send test calls
  worker_events.register(function(capabilities_list)
    local node_id = "control_plane"

    -- trigger cp's test
    local res, err = kong.rpc:call(node_id, "kong.test.notify_new_version")
    assert(res == true)
    assert(not err)

    ngx.log(ngx.DEBUG, "kong.sync.v2.notify_new_version ok")

  end, "clustering:jsonrpc", "connected")
end


return RpcSyncV2NotifyNewVersioinTestHandler
