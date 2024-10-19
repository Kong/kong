-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local cjson = require "cjson"
local pb = require "pb"
local kong = kong
local gzip = require("kong.tools.gzip")
local inflate_gzip = gzip.inflate_gzip
local ngx = ngx

local _M = {
  PRIORITY = 1001,
  VERSION = "1.0",
}


local function push_data(premature, data, config)
  if premature then
    return
  end

  local tcpsock = ngx.socket.tcp()
  tcpsock:settimeouts(10000, 10000, 10000)
  local ok, err = tcpsock:connect(config.host, config.port)
  if not ok then
    kong.log.err("connect err: ".. err .. " host: " .. config.host .. " port: " .. config.port)
    return
  end
  local _, err = tcpsock:send(data .. "\n")
  if err then
    kong.log.err(err)
  end
  tcpsock:close()
end


function _M:ws_client_frame(config)
  local data = kong.websocket.client.get_frame()
  local unzipped = inflate_gzip(data)
  local decoded = pb.decode("opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest", unzipped)

  -- ignore empty (keepalive) messages
  if #decoded.resource_spans == 0 then
    return
  end

  local json_data = cjson.encode(decoded)

  local ok, err = ngx.timer.at(0, push_data, json_data, config)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end

return _M
