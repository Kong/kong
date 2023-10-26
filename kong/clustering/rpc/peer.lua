local constants = require("constants")
local serializer = require("serializer")


local type = type
local assert = assert
local random = math.random
local setmetatable = setmetatable


local ERROR_CODE = constants.ERROR_CODE
local JSONRPC_VERSION = constants.JSONRPC_VERSION
local META_HELLO_MSG_ID = constants.META_HELLO_MSG_ID
local META_HELLO_METHOD = constants.META_HELLO_METHOD


local encode = serializer.encode


local PAYLOAD_T = {
  jsonrpc = JSONRPC_VERSION,
  id = 0,
  method = "",
  params = "",
}


local _M = {}
local _MT = { __index = _M, }


-- 1 is used by meta.v1.hello
local function gen_id()
    return random(2, 1e6)
end


function _M.new(hdl)
  local self = {
    handler = hdl,
  }

  return setmetatable(self, _MT)
end


function _M:validate(method, params)
  assert(type(method) == "string",
         "params must be a string")

  assert(type(params) == "table" or
         type(params) == "nil",
         "params must be a table or nil")

  if not self.handler:method_available(method) then
    return nil, method .. " is not available in peer"
  end

  return true
end


-- don't need response
function _M:notify(method, params, opts)
  local ok, err = self:validate(method, params)
  if not ok then
    return nil, err
  end

  PAYLOAD_T.id     = nil
  PAYLOAD_T.method = method
  PAYLOAD_T.params = params

  local data = encode(PAYLOAD_T)

  self.handler:push_send_encoded(data)

  return true
end


function _M:call(method, params, opts)
  local ok, err = self:validate(method, params)
  if not ok then
    return nil, { code = ERROR_CODE.INTERNAL_ERROR, message = err, }
  end

  local id = (method == META_HELLO_METHOD) and META_HELLO_MSG_ID or
             gen_id()

  PAYLOAD_T.id     = id
  PAYLOAD_T.method = method
  PAYLOAD_T.params = params

  local data = encode(PAYLOAD_T)

  -- send to peer
  self.handler:push_send_encoded(data)

  -- wait for response
  local res, err = self.handler:wait(id, opts and opts.timeout)

  if err then
    return nil, { code = ERROR_CODE.INTERNAL_ERROR, message = err, }
  end

  -- error occour
  if res.error then
    return nil, res.error
  end

  -- rpc ok
  return assert(res.result)
end


return _M
