-- by importing helpers, we ensure the kong PDK module is initialized
local helpers = require "spec.helpers"
local rpc_mgr = require("kong.clustering.rpc.manager")
local default_cert = require("spec.helpers.rpc_mock.default").default_cert
local uuid = require "kong.tools.uuid"


local _M = {}


local default_dp_conf = {
  role = "data_plane",
  cluster_control_plane = "localhost:8005",
}

setmetatable(default_dp_conf, { __index = default_cert })
local default_meta = { __index = default_dp_conf, }


local function do_nothing() end


local function client_stop(rpc_mgr)
  -- a hacky way to stop rpc_mgr from reconnecting
  rpc_mgr.try_connect = do_nothing

  -- this will stop all connections
  for _, socket in pairs(rpc_mgr.clients) do
    for conn in pairs(socket) do
      pcall(conn.stop, conn)
    end
  end
end


local function client_is_connected(rpc_mgr)
  for _, socket in pairs(rpc_mgr.clients) do
    if next(socket) then
      return true
    end
  end
  return false
end


local function client_wait_until_connected(rpc_mgr, timeout)
  return helpers.wait_until(function()
    return rpc_mgr:is_connected()
  end, timeout or 15)
end


-- TODO: let client not emits logs as it's expected to fail to connect for the first few seconds
function _M.new(opts)
  opts = opts or {}
  setmetatable(opts, default_meta)
  local ret = rpc_mgr.new(default_dp_conf, opts.name or uuid.uuid())

  ret.stop = client_stop
  ret.is_connected = client_is_connected
  ret.start = ret.try_connect
  ret.wait_until_connected = client_wait_until_connected

  return ret
end


return _M
