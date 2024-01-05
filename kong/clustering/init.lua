local _M = {}
local _MT = { __index = _M, }


local pl_tablex = require("pl.tablex")
local clustering_utils = require("kong.clustering.utils")
local events = require("kong.clustering.events")
local clustering_tls = require("kong.clustering.tls")
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

  local self = {
    conf = conf,
    cert = assert(get_cluster_cert(conf)),
    cert_key = assert(get_cluster_cert_key(conf)),
  }

  setmetatable(self, _MT)

  return self
end


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
  -- XXX: do not refactor or change the call signature of this function without
  -- reviewing the EE codebase first to sanity-check your changes
  cert_pem = cert_pem or ngx_var.ssl_client_raw_cert
  return validate_client_cert(self.conf, self.cert, cert_pem)
end


function _M:handle_cp_websocket()
  local cert, err = self:validate_client_cert()
  if not cert then
    ngx_log(ngx_ERR, _log_prefix, err)
    return ngx_exit(444)
  end

  return self.instance:handle_cp_websocket(cert)
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

  local role = self.conf.role

  if role == "control_plane" then
    self:init_cp_worker(basic_info)
    return
  end

  if role == "data_plane" then
    self:init_dp_worker(basic_info)
  end
end


return _M
