local semaphore = require "ngx.semaphore"
local semaphore_new = semaphore.new

local remove = table.remove
local insert = table.insert

-- buffer
local recv_buf = {}
local recv_buf_mt = { __index = recv_buf }

local default_timeout = 5

function recv_buf.new()
  return setmetatable({ smph = semaphore_new() }, recv_buf_mt)
end

function recv_buf:push(obj)
  insert(self, obj)
  if #self == 1 then
    self.smph:post()
  end

  return true
end

function recv_buf:pop_no_wait()
  return remove(self)
end

function recv_buf:pop(timeout)
  if #self == 0 then
    local ok, err = self.smph:wait(timeout or default_timeout)
    if not ok then
      return nil, err
    end
  end

  return remove(self)
end

-- end buffer

local unpack = unpack

local _M = {}
local mt = { __index = _M }

local empty = {}

-- we ignore mask problems and most of error handling

function _M:new(opts)
  opts = opts or empty

  local new_peer = setmetatable({
    timeout = opts.timeout,
    buf = recv_buf.new(),
  }, mt)

  return new_peer
end

function _M:set_timeout(time)
  self.timeout = time
  return true
end

local types = {
  [0x0] = "continuation",
  [0x1] = "text",
  [0x2] = "binary",
  [0x8] = "close",
  [0x9] = "ping",
  [0xa] = "pong",
}

function _M:translate_frame(fin, op, payload)
  payload = payload or ""
  local payload_len = #payload
  op = types[op]
  if op == "close" then
    -- being a close frame
    if payload_len > 0 then
      return payload[2], "close", payload[1]
    end

    return "", "close", nil
  end

  return payload, op, not fin and "again" or nil
end

function _M:recv_frame()
  local buf = self.buf
  local obj, err = buf:pop(self.timeout)
  if not obj then
    return nil, nil, err
  end

  return self:translate_frame(unpack(obj)) -- data, typ, err
end

local function send_frame(self, fin, op, payload)
  local message = { fin, op, payload }

  return self.peer.buf:push(message)
end

_M.send_frame = send_frame

function _M:send_text(data)
  return self:send_frame(true, 0x1, data)
end

function _M:send_binary(data)
  return self:send_frame(true, 0x2, data)
end

function _M:send_close(code, msg)
  local payload
  if code then
    payload = {code, msg}
  end
  return self:send_frame(true, 0x8, payload)
end

function _M:send_ping(data)
  return self:send_frame(true, 0x9, data)
end

function _M:send_pong(data)
  return self:send_frame(true, 0xa, data)
end

-- for clients
function _M.connect()
end
function _M.set_keepalive()
end
function _M.close()
end

return _M
