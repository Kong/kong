-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local assert = assert
local tostring = tostring


local _M = {
  PARSE_ERROR = -32700,
  INVALID_REQUEST = -32600,
  METHOD_NOT_FOUND = -32601,
  INVALID_PARAMS = -32602,
  INTERNAL_ERROR = -32603,
  SERVER_ERROR = -32000,
}


local ERROR_MSG = {
  [_M.PARSE_ERROR] = "Parse error",
  [_M.INVALID_REQUEST] = "Invalid Request",
  [_M.METHOD_NOT_FOUND] = "Method not found",
  [_M.INVALID_PARAMS] = "Invalid params",
  [_M.INTERNAL_ERROR] = "Internal error",
  [_M.SERVER_ERROR] = "Server error",
}


function _M.new_error(id, code, msg)
  if not msg then
    msg = assert(ERROR_MSG[code], "unknown code: " .. tostring(code))
  end

  return {
    jsonrpc = "2.0",
    id = id,
    error = {
      code = code,
      message = msg,
    }
  }
end


return _M
