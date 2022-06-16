-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local const = require "kong.enterprise_edition.constants"

return {
  headers = {
    id = "x-mock-websocket-request-id",
    self = "x-mock-websocket",
    multi = "x-mock-websocket-multi",
  },

  ports = {
    ws = 3000,
    wss = 3001,
  },

  -- token message values that the client sends to request
  -- connection metadata from the mock upstream server
  tokens = {
    request = "$_REQUEST",
    response = "$_RESPONSE",
  },

  opcode = const.WEBSOCKET.OPCODE_BY_TYPE,
  type = const.WEBSOCKET.TYPE_BY_OPCODE,
  status = const.WEBSOCKET.STATUS,
}
