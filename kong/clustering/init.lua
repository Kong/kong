local _M = {}
local _MT = { __index = _M, }


local pl_file = require("pl.file")
local pl_tablex = require("pl.tablex")
local ssl = require("ngx.ssl")
local openssl_x509 = require("resty.openssl.x509")
local clustering_utils = require("kong.clustering.utils")
local events = require("kong.clustering.events")


local assert = assert
local sort = table.sort


local is_dp_worker_process = clustering_utils.is_dp_worker_process


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
  end

  return self
end


function _M:handle_cp_websocket()
  return self.json_handler:handle_cp_websocket()
end


function _M:init_cp_worker(plugins_list)

  events.init()

  self.json_handler:init_worker(plugins_list)
end


function _M:init_dp_worker(plugins_list)
  local start_dp = function(premature)
    if premature then
      return
    end

    self.child = require("kong.clustering.data_plane").new(self.conf, self.cert, self.cert_key)
    self.child:init_worker(plugins_list)
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

  if role == "data_plane" and is_dp_worker_process() then
    self:init_dp_worker(plugins_list)
  end
end


return _M
