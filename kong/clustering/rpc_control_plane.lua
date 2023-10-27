local rpc_cp = require("kong.clustering.rpc.cp")


local _M = {}
local _MT = { __index = _M, }


function _M.new(clustering)
  local self = {
    plugins_map = {},
    conf = clustering.conf,
  }

  -- init rpc cp side
  local cp = rpc_cp.new({ "kong.sync.v1", "kong.test.v1", })
  kong.rpc = cp

  ngx.log(ngx.ERR, "rpc cp new ok")
  return setmetatable(self, _MT)
end



function _M:handle_cp_websocket()
  local rpc = assert(kong.rpc)

  ngx.log(ngx.ERR, "rpc cp run")
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
end


return _M
