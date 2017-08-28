local ngx_socket_udp = ngx.socket.udp
local ngx_log        = ngx.log
local table_concat   = table.concat
local setmetatable   = setmetatable
local NGX_ERR        = ngx.ERR
local NGX_DEBUG      = ngx.DEBUG
local fmt            = string.format
local tostring       = tostring


local stat_types = {
  gauge     = "g",
  counter   = "c",
  timer     = "ms",
  histogram = "h",
  meter     = "m",
  set       = "s",
}

local statsd_mt = {}
statsd_mt.__index = statsd_mt


function statsd_mt:new(conf)
  local sock   = ngx_socket_udp()
  local _, err = sock:setpeername(conf.host, conf.port)
  if err then
    return nil, fmt("failed to connect to %s:%s: %s", conf.host,
      tostring(conf.port), err)
  end

  local statsd = {
    host       = conf.host,
    port       = conf.port,
    prefix     = conf.prefix,
    socket     = sock,
    stat_types = stat_types,
  }
  return setmetatable(statsd, statsd_mt)
end


local function statsd_message(prefix, stat, delta, kind, sample_rate, tags)
  local rate = ""
  local str_tags = ""

  if sample_rate and sample_rate ~= 1 then
    rate = "|@" .. sample_rate
  end

  if tags and #tags > 0 then
    str_tags = "|#" .. table_concat(tags, ",")
  end

  return fmt("%s.%s:%s|%s%s%s", prefix, stat,
             delta, kind, rate, str_tags)
end


function statsd_mt:close_socket()
  local ok, err = self.socket:close()
  if not ok then
    ngx_log(NGX_ERR, "[udp-log] failed to close connection from ",
            self.host, ":", self.port, ": ", err)
  end
end


function statsd_mt:send_statsd(stat, delta, kind, sample_rate, tags)
  local udp_message = statsd_message(self.prefix or "kong", stat,
                                     delta, kind, sample_rate, tags)

  ngx_log(NGX_DEBUG, fmt("Sending data to statsd server: %s", udp_message))

  local ok, err = self.socket:send(udp_message)
  if not ok then
    ngx_log(NGX_ERR, fmt("failed to send data to %s:%s: %s", self.host,
      tostring(self.port), err))
  end
end


return statsd_mt
