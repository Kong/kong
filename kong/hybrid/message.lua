local _M = {}


local bit = require("bit")
local tablepool = require("tablepool")


local band, bor = bit.band, bit.bor
local lshift, rshift = bit.lshift, bit.rshift
local string_char, string_byte = string.char, string.byte


local POOL_NAME = "hybrid_messages"
local _MT = { __index = _M, }
local MAX_MESSAGE_SIZE = 64 * 1024 * 1024 - 1


--- convert a unsigned 32bit integer to network byte order
local function uint32_to_bytes(num)
  if num < 0 or num > 4294967295 then
    error("number " .. tostring(num) .. " out of range", 2)
  end

  return string_char(band(rshift(num, 24), 0xFF),
                     band(rshift(num, 16), 0xFF),
                     band(rshift(num, 8), 0xFF),
                     band(num, 0xFF))
end


local function bytes_to_uint32(str)
  assert(#str == 4)

  local b1, b2, b3, b4 = string_byte(str, 1, 4)

  return bor(lshift(b1, 24),
             lshift(b2, 16),
             lshift(b3, 8),
             b4)
end


function _M.new(src, dest, topic, message)
  local self = tablepool.fetch(POOL_NAME, 0, 4)

  assert(dest, "dest is required")
  assert(topic, "topic is required")
  assert(message, "message is required")
  assert(not src or #src < 256, "src must be under 256 bytes")
  assert(#dest < 256, "dest must be under 256 bytes")
  assert(#topic < 256, "topic must be under 256 bytes")
  assert(#message <= MAX_MESSAGE_SIZE, "message must be under 64MB")

  self.src = src
  self.dest = dest
  self.topic = topic
  self.message = message

  return setmetatable(self, _MT)
end


function _M:pack()
  return string_char(#self.src) .. self.src ..
         string_char(#self.dest) .. self.dest ..
         string_char(#self.topic) .. self.topic ..
         uint32_to_bytes(#self.message) .. self.message
end


function _M.unpack_from_socket(sock)
  local buf, err = sock:receive(1)
  if not buf then
    return nil, err
  end

  local src_len = string_byte(buf)
  local src
  src, err = sock:receive(src_len)
  if not src then
    return nil, err
  end

  buf, err = sock:receive(1)
  if not buf then
    return nil, err
  end
  local dest_len = string_byte(buf)
  local dest
  dest, err = sock:receive(dest_len)
  if not dest then
    return nil, err
  end

  buf, err = sock:receive(1)
  if not buf then
    return nil, err
  end
  local topic_len = string_byte(buf)
  local topic
  topic, err = sock:receive(topic_len)
  if not topic then
    return nil, err
  end

  buf, err = sock:receive(4)
  if not buf then
    return nil, err
  end
  local message_len = bytes_to_uint32(buf)
  if message_len > MAX_MESSAGE_SIZE then
    return nil, "peer attempted to send message that is larger than 64MB"
  end

  local message
  message, err = sock:receive(message_len)
  if not message then
    return nil, err
  end

  return _M.new(src, dest, topic, message)
end


function _M:release()
  tablepool.release(POOL_NAME, self)
end


return _M
