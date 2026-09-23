--- Mocked data plane for testing the control plane.
-- @module spec.helpers.rpc_mock.dp

local helpers = require "spec.helpers"
local rpc_mgr = require("kong.clustering.rpc.manager")
local default_cert = require("spec.helpers.rpc_mock.default").default_cert
local uuid = require("kong.tools.uuid")
local isempty = require("table.isempty")


local _M = {}


local default_dp_conf = {
  role = "data_plane",
  cluster_control_plane = "localhost:8005",
}

setmetatable(default_dp_conf, { __index = default_cert })
local default_meta = { __index = default_dp_conf, }


local function do_nothing() end


--- Stop the mocked data plane.
-- @function dp:stop
-- @treturn nil
local function dp_stop(rpc_mgr)
  -- a hacky way to stop rpc_mgr from reconnecting
  rpc_mgr.try_connect = do_nothing

  -- this will stop all connections
  for _, socket in pairs(rpc_mgr.clients) do
    for conn in pairs(socket) do
      pcall(conn.stop, conn)
    end
  end
end


--- Check if the mocked data plane is connected to the control plane.
-- @function dp:is_connected
-- @treturn boolean if the mocked data plane is connected to the control plane.
local function dp_is_connected(rpc_mgr)
  for _, socket in pairs(rpc_mgr.clients) do
    if not isempty(socket) then
      return true
    end
  end
  return false
end


--- Wait until the mocked data plane is connected to the control plane.
-- @function dp:wait_until_connected
-- @tparam number timeout The timeout in seconds. Throws If the timeout is reached.
local function dp_wait_until_connected(rpc_mgr, timeout)
  return helpers.wait_until(function()
    return rpc_mgr:is_connected()
  end, timeout or 15)
end


--- Start to connect the mocked data plane to the control plane.
-- @function dp:start
-- @treturn boolean if the mocked data plane is connected to the control plane.


-- TODO: let client not emits logs as it's expected when first connecting to CP
-- and when CP disconnects
function _M.new(opts)
  opts = opts or {}
  setmetatable(opts, default_meta)
  local ret = rpc_mgr.new(default_dp_conf, opts.name or uuid.uuid())

  ret.stop = dp_stop
  ret.is_connected = dp_is_connected
  ret.start = ret.try_connect
  ret.wait_until_connected = dp_wait_until_connected

  return ret
end


return _M
