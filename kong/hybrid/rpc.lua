local _M = {}


local message = require("kong.hybrid.message")
local msgpack = require("MessagePack")
local semaphore = require("ngx.semaphore")
local lrucache = require("resty.lrucache.pureffi")


local mp_pack = msgpack.pack
local mp_unpack = msgpack.unpack


local TOPIC_CALL = "rpc:call"
local TOPIC_RESULT = "rpc:result"
local _MT = { __index = _M, }


function _M.new(event_loop)
  local self = {
    next_seq = 1,
    callbacks = {},
    inflight = assert(lrucache.new(256)),
    loop = event_loop,
  }

  return setmetatable(self, _MT)
end


function _M:register(func_name, callback, no_thread)
  assert(not self.callbacks[func_name], func_name .. " already exists")

  self.callbacks[func_name] = { callback, no_thread, }
end


-- TODO: support for async, promise like interface?
function _M:call(dest, func_name, ...)
  local payload = {
    func_name = func_name,
    args = { ... },
    seq = self.next_seq,
  }
  self.next_seq = self.next_seq + 1

  local m = message.new(nil, dest, TOPIC_CALL, mp_pack(payload))
  local sema = semaphore.new()
  local inflight_table = { sema = sema, res = nil, err = nil,}
  self.inflight:set(payload.seq, inflight_table)

  local ok, err = self.loop:send(dest, m)
  if not ok then
    return nil, err
  end

  ok, err = sema:wait(10)
  if not ok then
    return nil, err
  end

  return inflight_table.res, inflight_table.err
end


function _M:handle_call(message)
  assert(message.topic == TOPIC_CALL)

  local payload = mp_unpack(message.message)


  local cb = assert(self.callbacks[payload.func_name])

  if cb[2] then
    local result

    local succ, res, err = pcall(cb[1], unpack(payload.args))
    if not succ then
      result = {
        succ = false,
        err = res,
        seq = payload.seq,
      }

    else
      result = {
        succ = not not res,
        err = err,
        seq = payload.seq,
      }
    end

    local m = message.new(nil, message.from, TOPIC_RESULT, mp_pack(result))
    self.loop:send(m)

  else -- need thread
    ngx.thread.spawn(function()
      local result

      local succ, res, err = pcall(cb[1], unpack(payload.args))
      if not succ then
        result = {
          succ = false,
          err = res,
          seq = payload.seq,
        }

      else
        result = {
          succ = not not res,
          err = err,
          seq = payload.seq,
        }
      end

      local m = message.new(nil, message.from, TOPIC_RESULT, mp_pack(result))
      self.loop:send(m)
    end)
  end
end


function _M:handle_result(message)
  assert(message.topic == TOPIC_RESULT)

  local payload = mp_unpack(message.message)

  local inflight_table = self.inflight:get(payload.seq)
  if not inflight_table then
    return nil, "could not locate inflight table for RPC with sequence " ..
                tostring(payload.seq)
  end

  inflight_table.res = payload.succ
  inflight_table.err = payload.err
  inflight_table.sema:post(1)
end


return _M
