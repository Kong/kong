local kong         = kong
local udp          = ngx.socket.udp
local concat       = table.concat
local setmetatable = setmetatable
local fmt          = string.format
local tostring     = tostring


local stat_types = {
  gauge        = "g",
  counter      = "c",
  timer        = "ms",
  histogram    = "h",
  meter        = "m",
  set          = "s",
  distribution = "d",
}


local statsd_mt = {}
statsd_mt.__index = statsd_mt

local env_datadog_agent_host = os.getenv 'KONG_DATADOG_AGENT_HOST'
local env_datadog_agent_port = tonumber(os.getenv 'KONG_DATADOG_AGENT_PORT' or "")

function statsd_mt:new(conf)
  local sock   = udp()
  local host = conf.host or env_datadog_agent_host
  local port = conf.port or env_datadog_agent_port

  local _, err = sock:setpeername(host, port)
  if err then
    return nil, fmt("failed to connect to %s:%s: %s", tostring(host),
                    tostring(port), err)
  end

  local statsd = {
    host       = host,
    port       = port,
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
    str_tags = "|#" .. concat(tags, ",")
  end

  return fmt("%s.%s:%s|%s%s%s", prefix, stat,
             delta, kind, rate, str_tags)
end


function statsd_mt:close_socket()
  local ok, err = self.socket:close()
  if not ok then
    kong.log.err("failed to close connection from ", self.host, ":", self.port,
                 ": ", err)
  end
end


function statsd_mt:send_statsd(stat, delta, kind, sample_rate, tags)
  local udp_message = statsd_message(self.prefix or "kong", stat,
                                     delta, kind, sample_rate, tags)

  kong.log.debug("Sending data to statsd server: ", udp_message)

  local ok, err = self.socket:send(udp_message)
  if not ok then
    kong.log.err("failed to send data to ", self.host, ":",
                 tostring(self.port), ": ", err)
  end
end


return statsd_mt
