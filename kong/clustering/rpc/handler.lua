local cjson = require("cjson.safe")
local semaphore = require("ngx.semaphore")


local constants = require("kong.clustering.rpc.constants")
local queue = require("kong.clustering.rpc.queue")
local serializer = require("kong.clustering.rpc.serializer")
local callbacks = require("kong.clustering.rpc.callbacks")


local type = type
local assert = assert
local setmetatable = setmetatable


local encode = serializer.encode
local decode = serializer.decode


local META_HELLO_MSG_ID = constants.META_HELLO_MSG_ID
local META_HELLO_METHOD = constants.META_HELLO_METHOD
local JSONRPC_VERSION = constants.JSONRPC_VERSION


local _M = {}
local _MT = { __index = _M, }


function _M.new()
  local self = {
    -- received response messages
    resp_semas = {},
    resp_msgs = {},

    -- received request messages
    req_msgs = queue.new(),

    -- ready to send messages
    send_msgs = queue.new(),

    -- kong.meta.v1.hello
    capabilities = {},
  }

  return setmetatable(self, _MT)
end


function _M:method_available(method)
  for cap, _ in pairs(self.capabilities) do
    if method:find(cap, 1, true) then
      return true
    end
  end

  if method == META_HELLO_METHOD then
    return true
  end

  return false
end


function _M:push_send(payload)
  local data = encode(payload)

  --ngx.log(ngx.ERR, "push_send: ", data)

  -- will be sent by websocket later
  return self.send_msgs:push(data)
end


-- data is already encoded
function _M:push_send_encoded(data)
  -- will be sent by websocket later
  return self.send_msgs:push(data)
end


function _M:pop_send(timeout)
  -- send by websocket
  return self.send_msgs:pop(timeout)
end


function _M:push_recv(data)
  --ngx.log(ngx.ERR, "push_recv: ", data)

  local payload = decode(data)
  if not payload then
    return
  end

  if payload.jsonrpc ~= JSONRPC_VERSION then
    return
  end

  -- rpc request, invoke rpc call
  if payload.method then

    -- kong.meta.v1.hello
    if payload.id == META_HELLO_MSG_ID and
       type(payload.params) == "table"
    then
      self.capabilities = payload.params
      ngx.log(ngx.ERR, "peer's capabilities is: ", cjson.encode(payload.params))
    end

    self.req_msgs:push(payload)
    return
  end

  -- rpc response
  if payload.error or payload.result then
    local id = payload.id

    -- illformed response, drop it
    if not id then
      return
    end

    -- check if a call is waiting
    local sema = self.resp_semas[id]

    -- rpc call cancel or timeout, drop it
    if not sema then
      return
    end

    -- kong.meta.v1.hello
    if payload.id == META_HELLO_MSG_ID and
       type(payload.result) == "table"
    then
      self.capabilities = payload.result
      ngx.log(ngx.ERR, "peer's capabilities is: ", cjson.encode(payload.result))
    end

    -- store result
    self.resp_msgs[id] = payload

    -- notify rpc client
    sema:post()
  end

  -- ignore others
end


-- called in a ngx.thread loop
function _M:invoke_callback()
  -- get a rpc request
  local payload, err = self.req_msgs:pop()

  if not payload then
    if err ~= "timeout" then
      ngx.log(ngx.ERR, "semaphore wait error: ", err)
    end

    -- timeout
    return
  end

  -- rpc call
  local data = callbacks.execute(payload)
  if not data then
    return
  end

  -- send back
  self:push_send_encoded(data)
end


function _M:wait(id, timeout)
  local sema = assert(semaphore.new())

  -- ensure result clean
  self.resp_msgs[id] = nil
  self.resp_semas[id] = sema

  -- wait push_recv
  local ok, err = sema:wait(timeout or 1)

  -- do not wait anymore
  self.resp_semas[id] = nil

  -- has no response
  if not ok then
    return nil, err
  end

  -- pop out result
  local res = self.resp_msgs[id]
  self.resp_msgs[id] = nil

  return res
end


return _M
