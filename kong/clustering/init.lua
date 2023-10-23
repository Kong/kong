-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}
local _MT = { __index = _M, }

local pl_tablex = require("pl.tablex")
local clustering_utils = require("kong.clustering.utils")
local events = require("kong.clustering.events")
local clustering_tls = require("kong.clustering.tls")
local clustering_telemetry = require("kong.clustering.telemetry")
local config_sync_backup = require "kong.clustering.config_sync_backup"
local wasm = require("kong.runloop.wasm")

local assert = assert
local sort = table.sort


local is_dp_worker_process = clustering_utils.is_dp_worker_process
local validate_client_cert = clustering_tls.validate_client_cert
local get_cluster_cert = clustering_tls.get_cluster_cert
local get_cluster_cert_key = clustering_tls.get_cluster_cert_key

local setmetatable = setmetatable
local ngx = ngx
local ngx_log = ngx.log
local ngx_var = ngx.var
local kong = kong
local ngx_exit = ngx.exit
local ngx_ERR = ngx.ERR


local _log_prefix = "[clustering] "


function _M.new(conf)
  assert(conf, "conf can not be nil", 2)

  -- we are assuming the new is called at init phase.
  if conf.cluster_fallback_config_export or conf.cluster_fallback_config_import then
    config_sync_backup.init(conf)
  end

  local self = {
    conf = conf,
    cert = assert(get_cluster_cert(conf)),
    cert_key = assert(get_cluster_cert_key(conf)),
  }

  setmetatable(self, _MT)

  return self
end


-- XXX EE
_M.telemetry_communicate = clustering_telemetry.telemetry_communicate
_M.register_server_on_message = clustering_telemetry.register_server_on_message
-- XXX EE


--- Validate the client certificate presented by the data plane.
---
--- If no certificate is passed in by the caller, it will be read from
--- ngx.var.ssl_client_raw_cert.
---
---@param cert_pem? string # data plane cert text
---
---@return boolean? success
---@return string?  error
function _M:validate_client_cert(cert_pem)
  cert_pem = cert_pem or ngx_var.ssl_client_raw_cert
  return validate_client_cert(self.conf, self.cert, cert_pem)
end


function _M:handle_cp_telemetry_websocket()
  local ok, err = self:validate_client_cert()
  if not ok then
    ngx_log(ngx_ERR, _log_prefix, err)
    return ngx_exit(444)
  end

  return clustering_telemetry.handle_cp_websocket()
end


function _M:handle_cp_websocket()
  local ok, err = self:validate_client_cert()
  if not ok then
    ngx_log(ngx_ERR, _log_prefix, err)
    return ngx_exit(444)
  end

  return self.instance:handle_cp_websocket()
end


function _M:init_cp_worker(basic_info)

  events.init()

  self.instance = require("kong.clustering.control_plane").new(self)
  self.instance:init_worker(basic_info)
end


function _M:init_dp_worker(basic_info)
  if not is_dp_worker_process() then
    return
  end

  self.instance = require("kong.clustering.data_plane").new(self)
  self.instance:init_worker(basic_info)
end


function _M:init_worker()
  local plugins_list = assert(kong.db.plugins:get_handlers())
  sort(plugins_list, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  plugins_list = pl_tablex.map(function(p)
    return { name = p.name, version = p.handler.VERSION, }
  end, plugins_list)

  local filters = {}
  if wasm.enabled() and wasm.filters then
    for _, filter in ipairs(wasm.filters) do
      filters[filter.name] = { name = filter.name }
    end
  end

  local basic_info = {
    plugins = plugins_list,
    filters = filters,
  }

  -- This must be initialized before clustering config sync.
  -- Otherwise the import/export may be triggered before state is ready.
  if self.conf.cluster_fallback_config_export then
    config_sync_backup.init_worker(self.conf, "exporter")

  elseif self.conf.cluster_fallback_config_import then
    config_sync_backup.init_worker(self.conf, "importer")
  end

  --[= XXX EE
  local role = self.conf.role
  if role == "control_plane" then
    self:init_cp_worker(basic_info)
  end
  --]=]

  if role == "data_plane" then
    self:init_dp_worker(basic_info)
  end
end


return _M
