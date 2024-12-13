-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local sandbox = require "kong.tools.sandbox".sandbox
local kong_meta = require "kong.meta"


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
    sock:close()
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
  VERSION = kong_meta.core_version,
}


function UdpLogHandler:log(conf)
  if conf.custom_fields_by_lua then
    local set_serialize_value = kong.log.set_serialize_value
    for key, expression in pairs(conf.custom_fields_by_lua) do
      set_serialize_value(key, sandbox(expression)())
    end
  end

  local ok, err = timer_at(0, log, conf, cjson.encode(kong.log.serialize()))
  if not ok then
    kong.log.err("could not create timer: ", err)
  end
end

-- EE [[
UdpLogHandler.ws_close = UdpLogHandler.log
-- ]]

return UdpLogHandler
