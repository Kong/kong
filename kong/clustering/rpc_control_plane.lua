local rpc_cp = require("kong.clustering.rpc.cp")


local _M = {}
local _MT = { __index = _M, }


function _M.new(clustering)
  assert(type(clustering) == "table",
         "kong.clustering is not instantiated")

  assert(type(clustering.conf) == "table",
         "kong.clustering did not provide configuration")

  local self = {
    plugins_map = {},
    conf = clustering.conf,

  }

  -- init rpc cp side
  local cp = rpc_cp.new({ "kong.sync.v1", "kong.test.v1", })
  kong.rpc = cp

  return setmetatable(self, _MT)
end



function _M:handle_rpc_websocket()
  --local dp_id = ngx_var.arg_node_id
  --local dp_hostname = ngx_var.arg_node_hostname
  --local dp_ip = ngx_var.remote_addr
  --local dp_version = ngx_var.arg_node_version

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
end


return _M
