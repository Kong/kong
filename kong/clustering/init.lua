local _M = {}
local _MT = { __index = _M, }


local pl_file = require("pl.file")
local pl_tablex = require("pl.tablex")
local ssl = require("ngx.ssl")
local openssl_x509 = require("resty.openssl.x509")
local ngx_log = ngx.log
local assert = assert
local sort = table.sort
local type = type


local check_protocol_support =
  require("kong.clustering.utils").check_protocol_support


local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG
local ngx_WARN = ngx.WARN


local _log_prefix = "[clustering] "


-- Sends "clustering", "push_config" to all workers in the same node, including self
local function post_push_config_event()
  local res, err = kong.worker_events.post("clustering", "push_config")
  if not res then
    ngx_log(ngx_ERR, _log_prefix, "unable to broadcast event: ", err)
  end
end


-- Handles "clustering:push_config" cluster event
local function handle_clustering_push_config_event(data)
  ngx_log(ngx_DEBUG, _log_prefix, "received clustering:push_config event for ", data)
  post_push_config_event()
end


-- Handles "dao:crud" worker event and broadcasts "clustering:push_config" cluster event
local function handle_dao_crud_event(data)
  if type(data) ~= "table" or data.schema == nil or data.schema.db_export == false then
    return
  end

  kong.cluster_events:broadcast("clustering:push_config", data.schema.name .. ":" .. data.operation)

  -- we have to re-broadcast event using `post` because the dao
  -- events were sent using `post_local` which means not all workers
  -- can receive it
  post_push_config_event()
end


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
  -- The "clustering:push_config" cluster event gets inserted in the cluster when there's
  -- a crud change (like an insertion or deletion). Only one worker per kong node receives
  -- this callback. This makes such node post push_config events to all the cp workers on
  -- its node
  kong.cluster_events:subscribe("clustering:push_config", handle_clustering_push_config_event)

  -- The "dao:crud" event is triggered using post_local, which eventually generates an
  -- ""clustering:push_config" cluster event. It is assumed that the workers in the
  -- same node where the dao:crud event originated will "know" about the update mostly via
  -- changes in the cache shared dict. Since data planes don't use the cache, nodes in the same
  -- kong node where the event originated will need to be notified so they push config to
  -- their data planes
  kong.worker_events.register(handle_dao_crud_event, "dao:crud")

  self.json_handler:init_worker(plugins_list)
  if not kong.configuration.legacy_hybrid_protocol then
      self.wrpc_handler:init_worker(plugins_list)
  end
end

function _M:init_dp_worker(plugins_list)
  local start_dp = function(premature)
    if premature then
      return
    end

    local config_proto, msg
    if not kong.configuration.legacy_hybrid_protocol then
      config_proto, msg = check_protocol_support(self.conf, self.cert, self.cert_key)
      -- otherwise config_proto = nil
    end

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

  if kong.configuration.legacy_hybrid_protocol then
    ngx_log(ngx_WARN, _log_prefix, "forcing to use legacy protocol (over WebSocket)")
  end

  if role == "control_plane" then
    self:init_cp_worker(plugins_list)
    return
  end

  if role == "data_plane" and ngx.worker.id() == 0 then
    self:init_dp_worker(plugins_list)
  end
end


return _M
