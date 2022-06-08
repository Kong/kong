local cjson = require "cjson"
local sandbox = require "kong.tools.sandbox".sandbox
local kong_meta = require "kong.meta"


local kong = kong
local ngx = ngx
local timer_at = ngx.timer.at
local udp = ngx.socket.udp


local sandbox_opts = { env = { kong = kong, ngx = ngx } }


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
  VERSION = kong_meta.version,
}


function UdpLogHandler:log(conf)
  if conf.custom_fields_by_lua then
    local set_serialize_value = kong.log.set_serialize_value
    for key, expression in pairs(conf.custom_fields_by_lua) do
      set_serialize_value(key, sandbox(expression, sandbox_opts)())
    end
  end

  local ok, err = timer_at(0, log, conf, cjson.encode(kong.log.serialize()))
  if not ok then
    kong.log.err("could not create timer: ", err)
  end
end


return UdpLogHandler
