local rpc_dp = require("kong.clustering.rpc.dp")


local _M = {}
local _MT = { __index = _M, }


local KONG_VERSION = kong.version


function _M.new(clustering)
  local conf = clustering.conf

  local self = {
    conf = conf,
    cert = clustering.cert,
    cert_key = clustering.cert_key,
  }

  local address = conf.cluster_control_plane .. "/v2/outlet"
  local uri = "wss://" .. address .. "?node_id=" ..
              kong.node.get_id() ..
              "&node_hostname=" .. kong.node.get_hostname() ..
              "&node_version=" .. KONG_VERSION

  ngx.log(ngx.ERR, "xxx uri = ", uri)

  local opts = {
    ssl_verify = true,
    client_cert = clustering.cert.cdata,
    client_priv_key = clustering.cert_key,
    --protocols = protocols,
  }

  if conf.cluster_mtls == "shared" then
    opts.server_name = "kong_clustering"

  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_server_name ~= "" then
      opts.server_name = conf.cluster_server_name
    end
  end

  local rpc_conf = {
    uri = uri,
    opts = opts,
  }

  -- init rpc dp side
  local dp = rpc_dp.new(rpc_conf, { "kong.sync.v1", "kong.test.v1", "kong.test.status.v1"})
  kong.rpc = dp

  return setmetatable(self, _MT)
end


function _M:init_worker(basic_info)
  -- ROLE = "data_plane"

  self.plugins_list = basic_info.plugins
  self.filters = basic_info.filters

  kong.rpc:init_worker()
end


return _M
