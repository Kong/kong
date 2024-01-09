local _M = {}
local _MT = { __index = _M, }


local server = require("resty.websocket.server")
local client = require("resty.websocket.client")
local socket = require("kong.clustering.rpc.socket")
local future = require("kong.clustering.rpc.future")
local utils = require("kong.clustering.rpc.utils")
local callbacks = require("kong.clustering.rpc.callbacks")
local queue = require("kong.clustering.rpc.queue")
local constants = require("kong.constants")
local table_isempty = require("table.isempty")


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
    -- node_id: { socket1 => true, socket2 => true, ... }
    clients = {},
    client_capabilities = {},
    node_id = node_id,
    conf = conf,
    callbacks = callbacks.new(),
    incoming = queue.new(4096),
  }

  self.callbacks:register("kong.meta.v1.capability_advertisement", function(node_id, capabilities)
    self.client_capabilities[node_id] = capabilities

    return self.callbacks:get_capabilities()
  end)

  return setmetatable(self, _MT)
end


function _M:_add_socket(socket)
  local sockets = self.clients[socket.node_id] or setmetatable({}, { __mode = "k", })

  assert(not sockets[socket])

  sockets[socket] = true

  self.clients[socket.node_id] = sockets
end


function _M:_remove_socket(socket)
  local sockets = assert(self.clients[socket.node_id])

  assert(sockets[socket])

  sockets[socket] = nil

  if table_isempty(sockets) then
    self.clients[socket.node_id] = nil
    self.client_capabilities[socket.node_id] = nil
  end
end


function _M:call(node_id, method, ...)
  local cap = utils.parse_method_name(method)

  if not self.client_capabilities[node_id] then
    return nil, "node is not connected, node_id: " .. node_id
  end

  if not self.client_capabilities[node_id][cap] then
    return nil, "requested capability does not exist, capability: " ..
                cap .. ", node_id: " .. node_id
  end

  local s = next(self.clients[node_id])

  local fut = future.new(s, method, { ... })
  assert(fut:start())

  local ok, err = fut:wait(5)
  if err then
    return nil, err
  end

  if ok then
    return fut.result
  end

  return fut.error.message
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

  local s = socket.new(self, wb, node_id)
  self:_add_socket(s)

  assert(s:start())
  local res, err = s:join()
  self:_remove_socket(s)

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
      "X-Kong-Version: " .. KONG_VERSION,
      "X-Kong-Node-Id: " .. self.node_id,
    },
  }

  if self.conf.cluster_mtls == "shared" then
    opts.server_name = "kong_clustering"

  else
    -- server_name will be set to the host if it is not explicitly defined here
    if self.conf.cluster_server_name ~= "" then
      opts.server_name = self.conf.cluster_server_name
    end
  end

  local reconnection_delay = math.random(5, 10)

  local c = assert(client:new(WS_OPTS))
  local ok, err = c:connect(uri, opts)
  if not ok then
    goto err
  end

  do
    local s = socket.new(self, c, node_id)

    -- capability advertisement
    local fut = future.new(s, "kong.meta.v1.capability_advertisement", { self.callbacks:get_capabilities(), })
    assert(fut:start())
    assert(s:start())

    ok, err = fut:wait(5)
    if not ok then
      s:stop()
      goto err
    end

    s.capabilities = ok
    ngx.log(ngx.ERR, "kong.meta.v1 resp: ", node_id, " cap: ", require("inspect")(ok))

    self:_add_socket(s)

    ok, err = s:join()
    self:_remove_socket(s)
  end

  if not ok then
    ngx_log(ngx_ERR, "[rpc] connection to node_id: ", node_id, " broken, err: ",
            err, ", reconnecting in ", reconnection_delay, " seconds")
  end

  ::err::

  if not exiting() then
    ngx.timer.at(reconnection_delay, function(premature)
      self:connect(premature, node_id, host, path, cert, key)
    end)
  end
end


return _M
