-- by importing helpers, we ensure the kong PDK module is initialized
local helpers = require "spec.helpers"
local rpc_mgr = require("kong.clustering.rpc.manager")
local default_cert_meta = require("spec.helpers.rpc_mock.default").default_cert_meta

local _M = {}
local _MT = { __index = _M, }

local default_dp_conf = {
  role = "data_plane",
  cluster_control_plane = "127.0.0.1",
}

setmetatable(default_dp_conf, default_cert_meta)
local default_meta = { __index = default_dp_conf, }

local function do_nothing() end

local function client_stop(rpc_mgr)
  -- a hacky way to stop rpc_mgr from reconnecting
  rpc_mgr.try_connect = do_nothing

  -- this will stop all connections
  for _, socket in rpc_mgr.sockets do
    socket:stop()
  end
end

function _M.new(opts)
  opts = opts or {}
  setmetatable(opts, default_meta)
  local ret = rpc_mgr.new(default_dp_conf, opts.name or "dp")
  ret.stop = client_stop
end

return _M
