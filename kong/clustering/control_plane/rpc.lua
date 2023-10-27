local lrucache = require("resty.lrucache")


local events = require("kong.clustering.events")
local rpc_cp = require("kong.clustering.rpc.cp")
local ping_svc = require("kong.clustering.control_plane.services.ping")


local _M = {}
local _MT = { __index = _M, }


function _M.new(clustering)
  local self = {
    plugins_map = {},
    conf = clustering.conf,

    -- init push flags
    init_pushed = {},

    -- last push config
    locks = assert(lrucache.new(4)),
  }

  -- init rpc services
  self.ping_svc = ping_svc.new()
  self.ping_svc:init()

  -- init rpc cp side
  local cp = rpc_cp.new({ "kong.test.v1", })
  kong.rpc = cp

  return setmetatable(self, _MT)
end



function _M:handle_cp_websocket()
  local dp_id = ngx.var.arg_node_id

  -- temp solution
  if not self.init_pushed[dp_id] then
    self.init_pushed[dp_id] = true

    ngx.log(ngx.ERR, "xxx time.at init push config")

    -- post events to push config
    ngx.timer.at(0.1, function()
      events.post_push_config_event()
    end)
  end

  local rpc = assert(kong.rpc)

  rpc:run()
end


function _M:init_worker(basic_info)
  --[[
  -- ROLE = "control_plane"
  local plugins_list = basic_info.plugins
  self.plugins_list = plugins_list
  self.plugins_map = plugins_list_to_map(plugins_list)

  self.plugins_configured = {}
  self.plugin_versions = {}

  for i = 1, #plugins_list do
    local plugin = plugins_list[i]
    self.plugin_versions[plugin.name] = plugin.version
  end

  self.filters = basic_info.filters
  --]]

  -- invoke rpc call
  events.clustering_push_config(function()
    local key = "last_push_config"
    local delay = self.conf.db_update_frequency

    local flag = self.locks:get(key)

    if not flag then
      -- 0: init a push
      self.locks:set(key, 0, delay)
      self:push_config()
      return
    end

    -- already has a schedule
    if flag >= 1 then
      --ngx.log(ngx.ERR, "xxx too many push, postpone ")
      return
    end

    ngx.log(ngx.ERR, "xxx try push config after some seconds")

    -- 1: scheduel a push after delay seconds
    self.locks:set(key, 1, delay)
    ngx.timer.at(delay, function(premature)
      self:push_config()
    end)

  end)
end


-- below are sync feature related


--local cjson = require("cjson.safe")
local declarative = require("kong.db.declarative")
local calculate_config_hash = require("kong.clustering.config_helper").calculate_config_hash


function _M:push_config()
  ngx.log(ngx.ERR, "try to push config to dp with rpc")

  local ok, payload, err = pcall(self.export_deflated_reconfigure_payload, self)
  if not ok then
    ngx.log(ngx.ERR, "unable to export config from database: ", err)
  end
  ngx.log(ngx.ERR, "export config from database ok")

  -- check_configuration_compatibility
  -- update_compatible_payload

  local rpc = kong.rpc

  local res, err = rpc:call("kong.sync.v1.push_all", { data = payload })
  if not res then
    ngx.log(ngx.ERR, "sync call error: ", err.message)
  else
    ngx.log(ngx.ERR, "receive from dp: ", res.msg)
  end

end


function _M:export_deflated_reconfigure_payload()
  local config_table, err = declarative.export_config()
  if not config_table then
    return nil, err
  end

  -- update plugins map
  self.plugins_configured = {}
  if config_table.plugins then
    for _, plugin in pairs(config_table.plugins) do
      self.plugins_configured[plugin.name] = true
    end
  end

  local config_hash, hashes = calculate_config_hash(config_table)

  local payload = {
    --type = "reconfigure",
    timestamp = ngx.now(),
    config_table = config_table,
    config_hash = config_hash,
    hashes = hashes,
  }

  --ngx.log(ngx.ERR, "xxx get payload")

  return payload, nil, config_hash
end


return _M
