local _M = {}


local message = require("kong.hybrid.message")
local event_loop = require("kong.hybrid.event_loop")
local msgpack = require("MessagePack")
local pl_stringx = require("pl.stringx")


local mp_pack = msgpack.pack
local tonumber = tonumber
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN


local KONG_VERSION = kong.version


function _M.new(parent)
  local self = {
    loop = event_loop.new(kong.node.get_id()),
  }

  return setmetatable(self, {
    __index = function(tab, key)
      return _M[key] or parent[key]
    end,
  })
end


function _M:init_worker()
  -- ROLE = "data_plane"

  self:start_timer(0)
end


function _M:start_timer(delay)
  if not delay then
    delay = math.random(5, 10)
  end

  if delay > 0 then
    ngx_log(ngx_WARN, "[hybrid-comm] reconnecting to control plane in ", delay, " seconds")
  end

  assert(ngx.timer.at(delay, function(premature)
    self:communicate(premature)
  end))
end


function _M:communicate(premature)
  if premature then
    -- worker wants to exit
    return
  end

  local conf = self.conf

  -- TODO: pick one random CP
  local address = conf.cluster_control_plane
  local host, _, port = pl_stringx.partition(address, ":")
  port = tonumber(port)

  local req = "GET /v2/outlet HTTP/1.1\r\nHost:" .. address ..
              "\r\nConnection: Upgrade\r\nUpgrade: Kong-Hybrid/2\r\n\r\n"

  local sock = ngx.socket.tcp()

  local res, err = sock:connect(host, port)
  if not res then
    ngx_log(ngx_ERR, "[hybrid-comm] connection to control plane ", address, " failed: ", err)
    self:start_timer()
    return
  end

  local opts = {
    ssl_verify = true,
    client_cert = self.cert,
    client_priv_key = self.cert_key,
  }

  if conf.cluster_mtls == "shared" then
    opts.server_name = "kong_clustering"

  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_server_name ~= "" then
      opts.server_name = conf.cluster_server_name
    end
  end

  res, err = sock:tlshandshake(opts)
  if not res then
    ngx_log(ngx_ERR, "[hybrid-comm] TLS handshake to control plane ", address,
                     " failed: ", err)
    self:start_timer()
    return
  end

  res, err = sock:send(req)
  if not res then
    ngx_log(ngx_ERR, "[hybrid-comm] sending HTTP header to control plane ",
                     address, " failed: ", err)
    self:start_timer()
    return
  end

  local header_reader = sock:receiveuntil("\r\n\r\n")
  local header, err, _ = header_reader()
  if not header then
    ngx_log(ngx_ERR, "[hybrid-comm] failed to receive response header: ", err)
    self:start_timer()
    return
  end

  local m = ngx.re.match(header, [[^\s*HTTP/1\.1\s+]], "jo")
  if not m then
    ngx_log(ngx_ERR, "[hybrid-comm] bad HTTP response status line: ", header)
    self:start_timer()
    return
  end

  local basic_info = message.new(kong.node.get_id(), "control_plane", "basic_info", mp_pack({
    kong_version = KONG_VERSION,
    node_id = kong.node.get_id(),
  }))

  res, err = sock:send(basic_info:pack())
  if not res then
    ngx_log(ngx_ERR, "[hybrid-comm] unable to send basic info to " ..
                     "control plane ", address, " err: ", err)
    self:start_timer()
    return
  end

  -- fully established
  local res, err = self.loop:handle_peer("control_plane", sock)

  if not res then
    ngx_log(ngx_ERR, "[hybrid-comm] connection to control plane broken: ", err)
    self:start_timer()
    return
  end

  self:start_timer()
end


function _M:register_callback(topic, callback)
  return self.loop:register_callback(topic, callback)
end


function _M:send(message)
  return self.loop:send(message)
end


return _M
