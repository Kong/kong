local kong         = kong
local udp          = ngx.socket.udp
local setmetatable = setmetatable
local tostring     = tostring
local fmt          = string.format


local stat_types = {
  gauge     = "g",
  counter   = "c",
  timer     = "ms",
  histogram = "h",
  meter     = "m",
  set       = "s",
}


local function create_statsd_message(prefix, stat, delta, kind, sample_rate)
  local rate = ""
  if sample_rate and sample_rate ~= 1 then
    rate = "|@" .. sample_rate
  end

  return fmt("%s.%s:%s|%s%s", prefix, stat, delta, kind, rate)
end


local statsd_mt = {}
statsd_mt.__index = statsd_mt


function statsd_mt:new(conf)
  local sock   = udp()
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


function statsd_mt:close_socket()
  local ok, err = self.socket:close()
  if not ok then
    kong.log.err("failed to close connection from ", self.host, ":",
                 tostring(self.port), ": ", err)
    return
  end
end


function statsd_mt:send_statsd(stat, delta, kind, sample_rate)
  local udp_message = create_statsd_message(self.prefix or "kong", stat,
                                            delta, kind, sample_rate)

  kong.log.debug("sending data to statsd server: %s", udp_message)

  local ok, err = self.socket:send(udp_message)
  if not ok then
    kong.log.err("failed to send data to ", self.host, ":",
                 tostring(self.port), ": ", err)
  end
end


return statsd_mt
