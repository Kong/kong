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
  if msg then
    if type(msg) ~= "string" then
      local mt = getmetatable(msg)
      -- other types without the metamethod `__tostring` don't
      -- generate a meaningful string, we should consider it as a
      -- bug since we should not expose something like
      -- `"table: 0x7fff0000"` to the RPC caller.
      assert(type(mt.__tostring) == "function")
    end

    msg = tostring(msg)

  else
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
