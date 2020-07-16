local cjson = require "cjson"


local kong = kong
local ngx = ngx
local timer_at = ngx.timer.at
local udp = ngx.socket.udp


local function log(premature, conf, str)
  if premature then
    return
  end

  local sock = udp()
  sock:settimeout(conf.timeout)

  local ok, err = sock:setpeername(conf.host, conf.port)
  if not ok then
    kong.log.err("could not connect to ", conf.host, ":", conf.port, ": ", err)
    return
  end

  ok, err = sock:send(str)
  if not ok then
    kong.log.err("could not send data to ", conf.host, ":", conf.port, ": ", err)

  else
    kong.log.debug("sent: ", str)
  end

  ok, err = sock:close()
  if not ok then
    kong.log.err("could not close ", conf.host, ":", conf.port, ": ", err)
  end
end


local UdpLogHandler = {
  PRIORITY = 8,
  VERSION = "2.0.1",
}


function UdpLogHandler:log(conf)
  local ok, err = timer_at(0, log, conf, cjson.encode(kong.log.serialize()))
  if not ok then
    kong.log.err("could not create timer: ", err)
  end
end


return UdpLogHandler
