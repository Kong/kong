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

local ok, new_tab = pcall(require, "table.new")
if not ok or type(new_tab) ~= "function" then
    new_tab = function (narr, nrec) return {} end
end

local ok, clear_tab = pcall(require, "table.clear")
if not ok then
  clear_tab = function (tab)
    for k, _ in pairs(tab) do
      tab[k] = nil
    end
  end
end

local DEFAULT_METRICS_COUNT = 11

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
  local sock
  if conf.use_tcp then
    sock = ngx_socket_tcp()
    sock:settimeout(1000)
    local _, err = sock:connect(conf.host, conf.port)
    if err then
      return nil, fmt("failed to connect to %s:%s: %s", conf.host,
                      tostring(conf.port), err)
    end
  else
    sock = ngx_socket_udp()
    local _, err = sock:setpeername(conf.host, conf.port)
    if err then
      return nil, fmt("failed to connect to %s:%s: %s", conf.host,
                      tostring(conf.port), err)
    end
  end

  local statsd = {
    host       = conf.host,
    port       = conf.port,
    prefix     = conf._prefix,
    socket     = sock,
    stat_types = stat_types,
    -- EE only
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
      ngx_log(NGX_DEBUG, "[statsd-advanced] sending last data to statsd server: ", message)
      local ok, err = self.socket:send(message)
      if not ok then
        ngx_log(NGX_ERR, fmt("[statsd-advanced] failed to send last data to %s:%s: %s", self.host,
                             tostring(self.port), err))
      end
    end

    local ok, err = self.socket:close()
    if not ok then
      ngx_log(NGX_ERR, fmt("[statsd-advanced] failed to close connection from %s:%s: %s", self.host,
                          tostring(self.port), err))
      return
    end
  end
end


function statsd_mt:send_statsd(stat, delta, kind, sample_rate)
  local message = create_statsd_message(self.prefix or "kong", stat,
                                            delta, kind, sample_rate)

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
                "[statsd-advanced] configured udp_packet_size is smaller than single message of length ",
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

  ngx_log(NGX_DEBUG, "[statsd-advanced] sending data to statsd server: ", message)

  local ok, err = self.socket:send(message)

  -- send the seperator for multi metrics
  if self.use_tcp and ok then
    ok, err = self.socket:send("\n")
  end
                                           
  if not ok then
    ngx_log(NGX_ERR, fmt("[statsd-advanced] failed to send data to %s:%s: %s", self.host,
                         tostring(self.port), err))
  end
end


return statsd_mt
