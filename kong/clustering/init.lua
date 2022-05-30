local _M = {}

local version_negotiation = require("kong.clustering.version_negotiation")
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


local _MT = { __index = _M, }


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
    self.json_handler = require("kong.clustering.control_plane").new(self.conf, self.cert_digest)
    self.wrpc_handler = require("kong.clustering.wrpc_control_plane").new(self.conf, self.cert_digest)
  end

  return self
end


function _M:request_version_negotiation()
  local response_data, err = version_negotiation.request_version_handshake(self.conf, self.cert, self.cert_key)
  if not response_data then
    ngx_log(ngx_ERR, _log_prefix, "error while requesting version negotiation: " .. err)
    assert(ngx.timer.at(math.random(5, 10), function(premature)
      self:communicate(premature)
    end))
    return
  end
end


function _M:handle_cp_websocket()
  return self.json_handler:handle_cp_websocket()
end

function _M:handle_wrpc_websocket()
  return self.wrpc_handler:handle_cp_websocket()
end

function _M:serve_version_handshake()
  return version_negotiation.serve_version_handshake(self.conf, self.cert_digest)
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
    self.json_handler.plugins_list = plugins_list
    self.wrpc_handler.plugins_list = plugins_list

    self.json_handler:init_worker()
    self.wrpc_handler:init_worker()

    return
  end

  if role == "data_plane" and ngx.worker.id() == 0 then
    assert(ngx.timer.at(0, function(premature)
      if premature then
        return
      end

      self:request_version_negotiation()

      local config_proto, msg = version_negotiation.get_negotiated_service("config")
      if not config_proto and msg then
        ngx_log(ngx_ERR, _log_prefix, "error reading negotiated \"config\" service: ", msg)
      end

      ngx_log(ngx_DEBUG, _log_prefix, "config_proto: ", config_proto, " / ", msg)
      if config_proto == "v1" then
        self.child = require "kong.clustering.wrpc_data_plane".new(self.conf, self.cert, self.cert_key)

      elseif config_proto == "v0" or config_proto == nil then
        self.child = require "kong.clustering.data_plane".new(self.conf, self.cert, self.cert_key)
      end

      if self.child then
        self.child.plugins_list = plugins_list
        self.child:communicate()
      end
    end))
  end
end


return _M
