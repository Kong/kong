local _M = {}
local _MT = { __index = _M, }


local server = require("resty.websocket.server")
local client = require("resty.websocket.client")
local socket = require("kong.clustering.rpc.socket")
local future = require("kong.clustering.rpc.future")
local callbacks = require("kong.clustering.rpc.callbacks")


local ngx_var = ngx.var
local ngx_ERR = ngx.ERR
local ngx_log = ngx.log
local ngx_exit = ngx.exit
local exiting = ngx.worker.exiting


local WS_OPTS = {
  timeout = constants.CLUSTERING_TIMEOUT,
  max_payload_len = kong.configuration.cluster_max_payload,
}
local KONG_VERSION = kong.version


-- create a new RPC manager, node_id is own node_id
function _M.new(conf, node_id)
  local self = {
    clients = setmetatable({}, { __mode = "k", }),
    node_id = node_id,
    conf = conf,
    callbacks = callbacks.new(),
  }

  callbacks:register("kong.meta.v1", function(node_id, capabilities)
    self.clients[node_id].capabilities = capabilities


    return self.callbacks:get_capabilities()
  end)

  return setmetatable(self, _MT)
end


function _M:call(node_id, method, params)
  local sock = self.clients[node_id]
  if not sock then
    return nil, "unknown node: " .. tostring(node_id)
  end

  local fut = sock:call(method, params)
  return fut:wait()
end


-- handle incoming client connections
function _M:handle_websocket()
  local client_version = ngx_var.http_x_kong_version
  local node_id = ngx_var.http_x_kong_node_id
  local meta_call = ngx_var.http_sec_websocket_protocol

  if not client_version then
    ngx_log(ngx_ERR, "[rpc] client did not provide version number")
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  if not node_id then
    ngx_log(ngx_ERR, "[rpc] client did not provide node ID")
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  if not meta_call then
    ngx_log(ngx_ERR, "[rpc] client did not provide Sec-WebSocket-Protocol, doesn't know how to negotiate")
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  -- TODO auth

  local wb, err = server:new(WS_OPTS)
  if not wb then
    ngx_log(ngx_ERR, "[rpc] unable to establish WebSocket connection with client: ", err)
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  local s = socket.new(wb, node_id)
  self.clients[node_id] = s

  local res, err = s:start()
  self.clients[node_id] = nil

  if not res then
    ngx_log(ngx_ERR, "[rpc] RPC connection broken: ", err, " node_id: ", node_id)
    return ngx_exit(ngx.ERROR)
  end

  return ngx_exit(ngx.OK)
end


function _M:connect(premature, node_id, host, path, cert, key)
  if premature then
    return
  end

  local uri = "wss://" .. host .. path

  local opts = {
    ssl_verify = true,
    client_cert = cert,
    client_priv_key = key,
    protocols = "kong.meta.v1",
    headers = {
      ["X-Kong-Version"] = KONG_VERSION,
      ["X-Kong-Node-Id"] = kong.node.get_id(),
    },
  }

  if conf.cluster_mtls == "shared" then
    opts.server_name = "kong_clustering"

  else
    -- server_name will be set to the host if it is not explicitly defined here
    if self.conf.cluster_server_name ~= "" then
      opts.server_name = self.conf.cluster_server_name
    end
  end

  local c = assert(client:new(WS_OPTS))
  local ok, err = c:connect(uri, opts)
  if not ok then
    goto err
  end

  local s = socket.new(c, node_id)

  -- capability advertisement
  local fut = future.new(s, "kong.meta.v1", self.callbacks:get_capabilities())
  assert(fut:start())
  assert(s:start())

  ok, err = fut:wait(5)
  if not ok then
    s:stop()
    goto err
  end

  s.capabilities = ok

  self.clients[node_id] = s

  ok, err = s:join()
  self.clients[node_id] = nil

  local reconnection_delay = math.random(5, 10)

  if not ok then
    ngx_log(ngx_ERR, "[rpc] connection to node_id: ", node_id, " broken, err: ",
            err, ", reconnecting in " .. reconnection_delay " seconds")
  end

  ::err::

  if not exiting() then
    ngx.timer.at(reconnection_delay, function(premature)
      self:connect(premature, node_id, host, path, cert, key)
    end)
  end
end


return _M
