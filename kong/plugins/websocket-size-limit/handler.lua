-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


---@class kong.plugin.websocket-size-limit.handler
local WebSocketSizeLimit = {
  PRIORITY = 1003,
  VERSION = require("kong.meta").core_version,
}

---@param conf kong.plugin.websocket-size-limit.conf
function WebSocketSizeLimit:ws_handshake(conf)
  local ws = kong.websocket

  if conf.client_max_payload then
    ws.client.set_max_payload_size(conf.client_max_payload)
  end

  if conf.upstream_max_payload then
    ws.upstream.set_max_payload_size(conf.upstream_max_payload)
  end
end


return WebSocketSizeLimit
