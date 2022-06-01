local _M = {}
local _MT = { __index = _M, }


local pl_file = require("pl.file")
local pl_tablex = require("pl.tablex")
local ssl = require("ngx.ssl")
local openssl_x509 = require("resty.openssl.x509")
local ngx_log = ngx.log
local assert = assert
local sort = table.sort

local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG

local _log_prefix = "[clustering] "

local check_protocol_support =
  require("kong.clustering.utils").check_protocol_support


function _M.new(conf)
  assert(conf, "conf can not be nil", 2)

  local self = {
    conf = conf,
  }

  setmetatable(self, _MT)

  local cert = assert(pl_file.read(conf.cluster_cert))
  self.cert = assert(ssl.parse_pem_cert(cert))

  cert = openssl_x509.new(cert, "PEM")
  self.cert_digest = cert:digest("sha256")

  local key = assert(pl_file.read(conf.cluster_cert_key))
  self.cert_key = assert(ssl.parse_pem_priv_key(key))

  if conf.role == "control_plane" then
    self.json_handler =
      require("kong.clustering.control_plane").new(self.conf, self.cert_digest)

    self.wrpc_handler =
      require("kong.clustering.wrpc_control_plane").new(self.conf, self.cert_digest)
  end

  return self
end


function _M:handle_cp_websocket()
  return self.json_handler:handle_cp_websocket()
end

function _M:handle_wrpc_websocket()
  return self.wrpc_handler:handle_cp_websocket()
end

function _M:init_cp_worker(plugins_list)
  self.json_handler:init_worker(plugins_list)
  self.wrpc_handler:init_worker(plugins_list)
end

function _M:init_dp_worker(plugins_list)
  local start_dp = function(premature)
    if premature then
      return
    end

    local config_proto, msg = check_protocol_support(self.conf, self.cert, self.cert_key)

    if not config_proto and msg then
      ngx_log(ngx_ERR, _log_prefix, "error check protocol support: ", msg)
    end

    ngx_log(ngx_DEBUG, _log_prefix, "config_proto: ", config_proto, " / ", msg)

    local data_plane
    if config_proto == "v0" or config_proto == nil then
      data_plane = "kong.clustering.data_plane"

    else -- config_proto == "v1" or higher
      data_plane = "kong.clustering.wrpc_data_plane"
    end

    self.child = require(data_plane).new(self.conf, self.cert, self.cert_key)

    if self.child then
      self.child:init_worker(plugins_list)
    end
  end

  assert(ngx.timer.at(0, start_dp))
end

function _M:init_worker()
  local plugins_list = assert(kong.db.plugins:get_handlers())
  sort(plugins_list, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  plugins_list = pl_tablex.map(function(p)
    return { name = p.name, version = p.handler.VERSION, }
  end, plugins_list)

  local role = self.conf.role

  if role == "control_plane" then
    self:init_cp_worker(plugins_list)
    return
  end

  if role == "data_plane" and ngx.worker.id() == 0 then
    self:init_dp_worker(plugins_list)
  end
end


return _M
