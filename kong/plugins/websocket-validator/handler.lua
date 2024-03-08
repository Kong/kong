-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local const = require "kong.enterprise_edition.constants"
local draft4 = require "kong.tools.json-schema.draft4"


local decode, null
do
  local cjson = require("cjson.safe").new()
  cjson.decode_array_with_array_mt(true)
  decode = cjson.decode
  null = cjson.null
end


local kong = kong
local pdk = kong.websocket
local status = const.WEBSOCKET.STATUS.INVALID_DATA
local rawset = rawset


local generators = {
  draft4 = function(schema)
    local validate, err = draft4.generate(schema)
    assert(validate, err)

    return function(data)
      local json, jerr = decode(data)
      if jerr then
        return nil, jerr
      end

      return validate(json)
    end
  end,
}


local validators = setmetatable({}, {
  __mode = "k",

  __index = function(self, conf)
    local fn = generators[conf.type](conf.schema)
    rawset(self, conf, fn)
    return fn
  end,
})


---@param peer "client"|"upstream"
---@param conf kong.plugin.websocket-validator.conf.peer
---@param typ resty.websocket.protocol.type
---@param data string
local function validate_frame(peer, conf, typ, data)
  local validation = conf and conf[typ]

  if validation and validation ~= null then
    local _, err = validators[validation](data)
    if err then
      kong.log.debug("closing WebSocket connection after receiving invalid ",
                     " frame from peer (", peer, "): ", err)
      -- control frames have a max size of 125 bytes, so sending the validation
      -- error in the close frame is a no-go. Maybe later we'll add a `send()`
      -- function to the PDK so that we can send a text frame and _then_ send
      -- a close frame afterwards.
      return pdk[peer].close(status.CODE, status.REASON)
    end
  end
end


---@class kong.plugin.websocket-validator.handler
local WebSocketValidator = {
  PRIORITY = 1006,
  VERSION = require("kong.meta").core_version,
}


---@param conf kong.plugin.websocket-validator.conf
function WebSocketValidator:ws_client_frame(conf, typ, data)
  validate_frame("client", conf.client, typ, data)
end


---@param conf kong.plugin.websocket-validator.conf
function WebSocketValidator:ws_upstream_frame(conf, typ, data)
  validate_frame("upstream", conf.upstream, typ, data)
end


return WebSocketValidator
