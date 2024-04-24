local _M = {}
local _MT = { __index = _M, }


local server = require("resty.websocket.server")
local client = require("resty.websocket.client")
local socket = require("kong.clustering.rpc.socket")
local concentrator = require("kong.clustering.rpc.concentrator")
local future = require("kong.clustering.rpc.future")
local utils = require("kong.clustering.rpc.utils")
local callbacks = require("kong.clustering.rpc.callbacks")
local clustering_tls = require("kong.clustering.tls")
local constants = require("kong.constants")
local table_isempty = require("table.isempty")
local pl_tablex = require("pl.tablex")
local cjson = require("cjson.safe")


local ngx_var = ngx.var
local ngx_ERR = ngx.ERR
local ngx_log = ngx.log
local ngx_exit = ngx.exit
local ngx_time = ngx.time
local exiting = ngx.worker.exiting
local pl_tablex_makeset = pl_tablex.makeset
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode
local validate_client_cert = clustering_tls.validate_client_cert
local CLUSTERING_PING_INTERVAL = constants.CLUSTERING_PING_INTERVAL


local WS_OPTS = {
  timeout = constants.CLUSTERING_TIMEOUT,
  max_payload_len = kong.configuration.cluster_max_payload,
}
local KONG_VERSION = kong.version


-- create a new RPC manager, node_id is own node_id
function _M.new(conf, node_id)
  local self = {
    -- clients[node_id]: { socket1 => true, socket2 => true, ... }
    clients = {},
    client_capabilities = {},
    node_id = node_id,
    conf = conf,
    cluster_cert = assert(clustering_tls.get_cluster_cert(conf)),
    cluster_cert_key = assert(clustering_tls.get_cluster_cert_key(conf)),
    callbacks = callbacks.new(),
  }

  self.concentrator = concentrator.new(self, kong.db)

  return setmetatable(self, _MT)
end


function _M:_add_socket(socket, capabilities_list)
  local sockets = self.clients[socket.node_id]
  if not sockets then
    assert(self.concentrator:_enqueue_subscribe(socket.node_id))
    sockets = setmetatable({}, { __mode = "k", })
    self.clients[socket.node_id] = sockets
  end

  self.client_capabilities[socket.node_id] = {
    set = pl_tablex_makeset(capabilities_list),
    list = capabilities_list,
  }

  assert(not sockets[socket])

  sockets[socket] = true
end


function _M:_remove_socket(socket)
  local sockets = assert(self.clients[socket.node_id])

  assert(sockets[socket])

  sockets[socket] = nil

  if table_isempty(sockets) then
    self.clients[socket.node_id] = nil
    self.client_capabilities[socket.node_id] = nil
    assert(self.concentrator:_enqueue_unsubscribe(socket.node_id))
  end
end


-- Helper that finds a node by node_id and check
-- if capability is supported
-- Returns: "local" if found locally,
-- or "concentrator" if found from the concentrator
-- In case of error, return nil, err instead
function _M:_find_node_and_check_capability(node_id, cap)
  if self.client_capabilities[node_id] then
    if not self.client_capabilities[node_id].set[cap] then
      return nil, "requested capability does not exist, capability: " ..
                  cap .. ", node_id: " .. node_id
    end

    return "local"
  end

  -- does concentrator knows more about this client?
  local res, err = kong.db.clustering_data_planes:select({ id = node_id })
  if err then
    return nil, "unable to query concentrator " .. err
  end

  if not res or ngx_time() - res.last_seen > CLUSTERING_PING_INTERVAL * 2 then
    return nil, "node is not connected, node_id: " .. node_id
  end

  for _, c in ipairs(res.rpc_capabilities) do
    if c == cap then
      return "concentrator"
    end
  end

  return nil, "requested capability does not exist, capability: " ..
              cap .. ", node_id: " .. node_id
end


-- low level helper used internally by :call() and concentrator
-- this one does not consider forwarding using concentrator
-- when node does not exist
function _M:_local_call(node_id, method, params)
  if not self.client_capabilities[node_id] then
    return nil, "node is not connected, node_id: " .. node_id
  end

  local cap = utils.parse_method_name(method)
  if not self.client_capabilities[node_id].set[cap] then
    return nil, "requested capability does not exist, capability: " ..
                cap .. ", node_id: " .. node_id
  end

  local s = next(self.clients[node_id]) -- TODO: better LB?

  local fut = future.new(node_id, s, method, params)
  assert(fut:start())

  local ok, err = fut:wait(5)
  if err then
    return nil, err
  end

  if ok then
    return fut.result
  end

  return nil, fut.error.message
end


-- public interface, try call on node_id locally first,
-- if node is not connected, try concentrator next
function _M:call(node_id, method, ...)
  local cap = utils.parse_method_name(method)

  local res, err = self:_find_node_and_check_capability(node_id, cap)
  if not res then
    return nil, err
  end

  local params = {...}

  if res == "local" then
    res, err = self:_local_call(node_id, method, params)
    if not res then
      return nil, err
    end

    return res
  end

  assert(res == "concentrator")

  -- try concentrator
  local fut = future.new(node_id, self.concentrator, method, params)
  assert(fut:start())

  local ok, err = fut:wait(5)
  if err then
    return nil, err
  end

  if ok then
    return fut.result
  end

  return nil, fut.error.message
end


-- handle incoming client connections
function _M:handle_websocket()
  local kong_version = ngx_var.http_x_kong_version
  local node_id = ngx_var.http_x_kong_node_id
  local rpc_protocol = ngx_var.http_sec_websocket_protocol
  local content_encoding = ngx_var.http_content_encoding
  local rpc_capabilities = ngx_var.http_x_kong_rpc_capabilities

  if not kong_version then
    ngx_log(ngx_ERR, "[rpc] client did not provide version number")
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  if not node_id then
    ngx_log(ngx_ERR, "[rpc] client did not provide node ID")
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  if content_encoding ~= "x-snappy-framed" then
    ngx_log(ngx_ERR, "[rpc] client does use Snappy compressed frames")
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  if rpc_protocol ~= "kong.rpc.v1" then
    ngx_log(ngx_ERR, "[rpc] unknown RPC protocol: " ..
                     tostring(rpc_protocol) ..
                     ", doesn't know how to communicate with client")
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  if not rpc_capabilities then
    ngx_log(ngx_ERR, "[rpc] client did not provide capability list")
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  rpc_capabilities = cjson_decode(rpc_capabilities)
  if not rpc_capabilities then
    ngx_log(ngx_ERR, "[rpc] failed to decode client capability list")
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  local cert, err = validate_client_cert(self.conf, self.cluster_cert, ngx_var.ssl_client_raw_cert)
  if not cert then
    ngx_log(ngx_ERR, "[rpc] client's certificate failed validation: ", err)
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  ngx.header["X-Kong-RPC-Capabilities"] = cjson_encode(self.callbacks:get_capabilities_list())

  local wb, err = server:new(WS_OPTS)
  if not wb then
    ngx_log(ngx_ERR, "[rpc] unable to establish WebSocket connection with client: ", err)
    return ngx_exit(ngx.HTTP_CLOSE)
  end

  local s = socket.new(self, wb, node_id)
  self:_add_socket(s, rpc_capabilities)

  s:start()
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
    protocols = "kong.rpc.v1",
    headers = {
      "X-Kong-Version: " .. KONG_VERSION,
      "X-Kong-Node-Id: " .. self.node_id,
      "X-Kong-Hostname: " .. kong.node.get_hostname(),
      "X-Kong-RPC-Capabilities: " .. cjson_encode(self.callbacks:get_capabilities_list()),
      "Content-Encoding: x-snappy-framed"
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
    ngx_log(ngx_ERR, "[rpc] unable to connect to peer: ", err)
    goto err
  end

  do
    local resp_headers = c:get_resp_headers()
    -- FIXME: resp_headers should not be case sensitive
    if not resp_headers or not resp_headers["x_kong_rpc_capabilities"] then
      ngx_log(ngx_ERR, "[rpc] peer did not provide capability list, node_id: ", node_id)
      c:send_close() -- can't do much if this fails
      goto err
    end

    local capabilities = resp_headers["x_kong_rpc_capabilities"]
    capabilities = cjson_decode(capabilities)
    if not capabilities then
      ngx_log(ngx_ERR, "[rpc] unable to decode peer capability list, node_id: ", node_id,
                       " list: ", capabilities)
      c:send_close() -- can't do much if this fails
      goto err
    end

    local s = socket.new(self, c, node_id)
    s:start()
    self:_add_socket(s, capabilities)

    ok, err = s:join() -- main event loop

    self:_remove_socket(s)

    if not ok then
      ngx_log(ngx_ERR, "[rpc] connection to node_id: ", node_id, " broken, err: ",
              err, ", reconnecting in ", reconnection_delay, " seconds")
    end
  end

  ::err::

  if not exiting() then
    ngx.timer.at(reconnection_delay, function(premature)
      self:connect(premature, node_id, host, path, cert, key)
    end)
  end
end


function _M:get_peers()
  local res = {}

  for node_id, cap in pairs(self.client_capabilities) do
    res[node_id] = cap.list
  end

  return res
end


return _M
