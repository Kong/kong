local ngx_socket_udp = ngx.socket.udp
local ngx_log = ngx.log
local table_concat = table.concat
local setmetatable = setmetatable
local NGX_ERR = ngx.ERR
local NGX_DEBUG = ngx.DEBUG

local statsd_mt = {}
statsd_mt.__index = statsd_mt

function statsd_mt:new(conf)
  local sock = ngx_socket_udp()
  local _, err = sock:setpeername(conf.host, conf.port)
  if err then
    return nil, "failed to connect to "..conf.host..":"..tostring(conf.port)..": "..err
  end

  local statsd = {
    host = conf.host,
    port = conf.port,
    socket = sock
  }
  return setmetatable(statsd, statsd_mt)
end

function statsd_mt:create_statsd_message(stat, delta, kind, sample_rate)
  local rate = ""
  if sample_rate and sample_rate ~= 1 then
    rate = "|@"..sample_rate
  end

  local message = {
    "kong.",
    stat,
    ":",
    delta,
    "|",
    kind,
    rate
  }
  return table_concat(message, "")
end

function statsd_mt:close_socket()
  local ok, err = self.socket:close()
  if not ok then
    ngx_log(NGX_ERR, "failed to close connection from "..self.host..":"..tostring(self.port)..": ", err)
    return
  end
end

function statsd_mt:send_statsd(stat, delta, kind, sample_rate)
  local udp_message = self:create_statsd_message(stat, delta, kind, sample_rate)
  ngx_log(NGX_DEBUG, "Sending data to statsd server: "..udp_message)
  local ok, err = self.socket:send(udp_message)
  if not ok then
    ngx_log(NGX_ERR, "failed to send data to "..self.host..":"..tostring(self.port)..": ", err)
  end
end

function statsd_mt:gauge(stat, value, sample_rate)
  return self:send_statsd(stat, value, "g", sample_rate)
end

function statsd_mt:counter(stat, value, sample_rate)
  return self:send_statsd(stat, value, "c", sample_rate)
end

function statsd_mt:timer(stat, ms)
  return self:send_statsd(stat, ms, "ms")
end

function statsd_mt:histogram(stat, value)
  return self:send_statsd(stat, value, "h")
end

function statsd_mt:meter(stat, value)
  return self:send_statsd(stat, value, "m")
end

function statsd_mt:set(stat, value)
  return self:send_statsd(stat, value, "s")
end

return statsd_mt
