local rpc_cp = require("kong.clustering.rpc.cp")
local ping_svc = require("kong.clustering.services.ping")


local _M = {}
local _MT = { __index = _M, }


local function push_config(self)
  ngx.log(ngx.ERR, "try to push config to dp with rpc")
end


function _M.new(clustering)
  local self = {
    plugins_map = {},
    conf = clustering.conf,
  }

  self.ping_svc = ping_svc.new()
  self.ping_svc:init()

  -- init rpc cp side
  local cp = rpc_cp.new({ "kong.sync.v1", "kong.test.v1", })
  kong.rpc = cp

  return setmetatable(self, _MT)
end



function _M:handle_cp_websocket()
  local rpc = assert(kong.rpc)

  rpc:run()
end


function _M:init_worker(basic_info)
  --[[
  -- ROLE = "control_plane"
  local plugins_list = basic_info.plugins
  self.plugins_list = plugins_list
  self.plugins_map = plugins_list_to_map(plugins_list)

  self.deflated_reconfigure_payload = nil
  self.reconfigure_payload = nil
  self.plugins_configured = {}
  self.plugin_versions = {}

  for i = 1, #plugins_list do
    local plugin = plugins_list[i]
    self.plugin_versions[plugin.name] = plugin.version
  end

  self.filters = basic_info.filters
  --]]

  kong.worker_events.register(push_config, "clustering", "push_config")
end


return _M
