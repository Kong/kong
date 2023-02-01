local ngx_socket_udp = ngx.socket.udp
local ngx_socket_tcp = ngx.socket.tcp
local ngx_log        = ngx.log
local NGX_ERR        = ngx.ERR
local NGX_WARN       = ngx.WARN
local NGX_DEBUG      = ngx.DEBUG
local setmetatable   = setmetatable
local tostring       = tostring
local fmt            = string.format
local table_concat   = table.concat
local new_tab        = require "table.new"
local clear_tab      = require "table.clear"

local DEFAULT_METRICS_COUNT = 11

local stat_types = {
  gauge     = "g",
  counter   = "c",
  timer     = "ms",
  histogram = "h",
  meter     = "m",
  set       = "s",
}


-- tag style reference
-- 
-- For Librato-style tags, they must be appended to the metric name with a delimiting #, as so:
-- metric.name#tagName=val,tag2Name=val2:0|c
-- See the https://github.com/librato/statsd-librato-backend#tags README for a more complete description.
-- 
-- For InfluxDB-style tags, they must be appended to the metric name with a delimiting comma, as so:
-- metric.name,tagName=val,tag2Name=val2:0|c
-- See this https://www.influxdata.com/blog/getting-started-with-sending-statsd-metrics-to-telegraf-influxdb/#introducing-influx-statsd
-- for a larger overview.
--
-- For DogStatsD-style tags, they're appended as a |# delimited section at the end of the metric, as so:
-- metric.name:0|c|#tagName:val,tag2Name:val2
-- See Tags in https://docs.datadoghq.com/developers/dogstatsd/data_types/#tagging for the concept description and Datagram Format. 
-- 
-- For SignalFX dimension, add the tags to the metric name in square brackets, as so:
-- metric.name[tagName=val,tag2Name=val2]:0|c
-- See the https://github.com/signalfx/signalfx-agent/blob/main/docs/monitors/collectd-statsd.md#adding-dimensions-to-statsd-metrics
-- README for a more complete description.
local function create_statsd_message(prefix, stat, delta, kind, sample_rate, tags, tag)
  local rate = ""
  if sample_rate and sample_rate ~= 1 then
    rate = "|@" .. sample_rate
  end

  if tag == nil or tags == nil then
    return fmt("%s.%s:%s|%s%s", prefix, stat, delta, kind, rate)
  end
  
  local metrics = {}
  if tag == "dogstatsd" then
    for k,v in pairs(tags) do
      metrics[#metrics+1] = fmt("%s:%s", k, v)  
    end

    local metrics_tag_str = table_concat(metrics, ",")
    return fmt("%s.%s:%s|%s%s|#%s", prefix, stat, delta, kind, rate, metrics_tag_str)

  elseif tag == "influxdb" then
    for k,v in pairs(tags) do
      metrics[#metrics+1] = fmt("%s=%s", k, v)
    end

    local metrics_tag_str = table_concat(metrics, ",")
    return fmt("%s.%s,%s:%s|%s%s", prefix, stat, metrics_tag_str, delta, kind, rate)

  elseif tag == "librato" then
    for k,v in pairs(tags) do
      metrics[#metrics+1] = fmt("%s=%s", k, v)
    end

    local metrics_tag_str = table_concat(metrics, ",")
    return fmt("%s.%s#%s:%s|%s%s", prefix, stat, metrics_tag_str, delta, kind, rate)

  elseif tag == "signalfx" then
    for k,v in pairs(tags) do
      metrics[#metrics+1] = fmt("%s=%s", k, v)
    end

    local metrics_tag_str = table_concat(metrics, ",")
    return fmt("%s.%s[%s]:%s|%s%s", prefix, stat, metrics_tag_str, delta, kind, rate)
  end
end


local statsd_mt = {}
statsd_mt.__index = statsd_mt


function statsd_mt:new(conf)
  local sock, err, _
  if conf.use_tcp then
    sock = ngx_socket_tcp()
    sock:settimeout(1000)
    _, err = sock:connect(conf.host, conf.port)
  else
    sock = ngx_socket_udp()
    _, err = sock:setpeername(conf.host, conf.port)
  end

  if err then
    return nil, fmt("failed to connect to %s:%s: %s", conf.host,
      tostring(conf.port), err)
  end

  local statsd = {
    host       = conf.host,
    port       = conf.port,
    prefix     = conf._prefix,
    socket     = sock,
    stat_types = stat_types,
    udp_packet_size = conf.udp_packet_size,
    use_tcp         = conf.use_tcp,
    udp_buffer      = new_tab(DEFAULT_METRICS_COUNT, 0),
    udp_buffer_cnt  = 0,
    udp_buffer_size = 0,
  }
  return setmetatable(statsd, statsd_mt)
end


function statsd_mt:close_socket()
  if self.use_tcp then
    self.socket:setkeepalive()
  else
    -- send the buffered msg
    if self.udp_packet_size > 0 and self.udp_buffer_size > 0 then
      local message = table_concat(self.udp_buffer, "\n")
      ngx_log(NGX_DEBUG, "[statsd] sending last data to statsd server: ", message)
      local ok, err = self.socket:send(message)
      if not ok then
        ngx_log(NGX_ERR, fmt("[statsd] failed to send last data to %s:%s: %s", self.host,
                             tostring(self.port), err))
      end
    end

    local ok, err = self.socket:close()
    if not ok then
      ngx_log(NGX_ERR, fmt("[statsd] failed to close connection from %s:%s: %s", self.host,
                          tostring(self.port), err))
      return
    end
  end
end


function statsd_mt:send_statsd(stat, delta, kind, sample_rate, tags, tag)
  local message = create_statsd_message(self.prefix or "kong", stat,
                                            delta, kind, sample_rate, tags, tag)

  -- if buffer-and-send is enabled
  if not self.use_tcp and self.udp_packet_size > 0 then
    local message_size = #message
    local new_size = self.udp_buffer_size + message_size
    -- if we exceeded the configured pkt_size
    if new_size > self.udp_packet_size then
      local truncated = false
      if self.udp_buffer_size == 0 then
        truncated = true
        ngx_log(NGX_WARN,
                "[statsd] configured udp_packet_size is smaller than single message of length ",
                message_size,
                ", UDP packet may be truncated")
      end
      local current_message = message
      message = table_concat(self.udp_buffer, "\n")
      clear_tab(self.udp_buffer)
      self.udp_buffer_cnt = 1
      self.udp_buffer[1] = current_message
      self.udp_buffer_size = message_size
      if truncated then
        -- current message is buffered and will be sent in next call
        return
      end
    else -- if not, buffer the message
      local new_buffer_cnt = self.udp_buffer_cnt + 1
      self.udp_buffer_cnt = new_buffer_cnt
      self.udp_buffer[new_buffer_cnt] = message
      -- add length of \n
      self.udp_buffer_size = new_size + 1
      return
    end

  end

  ngx_log(NGX_DEBUG, "[statsd] sending data to statsd server: ", message)

  local ok, err = self.socket:send(message)

  -- send the seperator for multi metrics
  if self.use_tcp and ok then
    ok, err = self.socket:send("\n")
  end

  if not ok then
    ngx_log(NGX_ERR, fmt("[statsd] failed to send data to %s:%s: %s", self.host,
                         tostring(self.port), err))
  end
end


return statsd_mt
