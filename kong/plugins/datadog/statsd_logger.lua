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
  sock:settimeout(conf.timeout)
  local ok, err = sock:setpeername(conf.host, conf.port)
  if not ok then
    return nil, "failed to connect to "..conf.host..":"..conf.port..": "..err
  end

  local statsd = {
    host = conf.host,
    port = conf.port,
    socket = sock,
  }

  return setmetatable(statsd, statsd_mt)
end

function statsd_mt:create_statsd_message(stat, delta, kind, sample_rate, tags)
  local rate = ""
  local str_tags = ""
  if sample_rate and sample_rate ~= 1 then
    rate = "|@"..sample_rate
  end
  
  if tags and #tags > 0 then
    str_tags = "|#"..table_concat(tags, ",")
  end

  local message = {
    "kong.",
    stat,
    ":",
    delta,
    "|",
    kind,
    rate,
    str_tags
  }
  return table_concat(message, "")
end

function statsd_mt:close_socket()
  local ok, err = self.socket:close()
  if not ok then
    ngx_log(NGX_ERR, "[udp-log] failed to close connection from ", self.host, ":", self.port, ": ", err)
  end
end

function statsd_mt:send_statsd(stat, delta, kind, sample_rate, tags)
  local udp_message = self:create_statsd_message(stat, delta, kind, sample_rate, tags)

  ngx_log(NGX_DEBUG, "[udp-log] sending data to statsd server: ", udp_message)

  local ok, err = self.socket:send(udp_message)
  if not ok then
    ngx_log(NGX_ERR, "[udp-log] could not send data to ", self.host, ":", self.port, ": ", err)
  end
end

function statsd_mt:gauge(stat, value, sample_rate, tags)
  return self:send_statsd(stat, value, "g", sample_rate, tags)
end

function statsd_mt:counter(stat, value, sample_rate, tags)
  return self:send_statsd(stat, value, "c", sample_rate, tags)
end

function statsd_mt:timer(stat, ms, tags)
  return self:send_statsd(stat, ms, "ms", nil, tags)
end

function statsd_mt:histogram(stat, value, tags)
  return self:send_statsd(stat, value, "h", nil, tags)
end

function statsd_mt:meter(stat, value, tags)
  return self:send_statsd(stat, value, "m", nil, tags)
end

function statsd_mt:set(stat, value, tags)
  return self:send_statsd(stat, value, "s", nil, tags)
end

return statsd_mt
