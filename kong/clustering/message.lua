local _M = {}


local bit = require("bit")
local tablepool = require("tablepool")


local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift = bit.lshift, bit.rshift
local string_char, string_byte = string.char, string.byte


local POOL_NAME = "clustering_message"
local _MT = { __index = _M, }


--- convert a unsigned 32bit integer to network byte order
local function uint32_to_bytes(num)
  if num < 0 or num > 4294967295 then
    error("number " .. tostring(num) .. " out of range", 2)
  end

  return string_char(band(rshift(num, 24), 0xFF),
                     band(rshift(num, 16), 0xFF),
                     band(rshift(num, 8), 0xFF))
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
  local src_len = string_byte(sock:receive(1))
  local src, err = sock:receive(src_len)
  if not src then
    return nil, err
  end

  local dest_len = string_byte(sock:receive(1))
  local dest
  dest, err = sock:receive(dest_len)
  if not dest then
    return nil, err
  end

  local topic_len = string_byte(sock:receive(1))
  local topic
  topic, err = sock:receive(topic_len)
  if not topic then
    return nil, err
  end

  local message_len = bytes_to_uint32(sock:receive(4))
  local message
  message, err = sock:receive(message_len)
  if not message then
    return nil, err
  end

  return _M.new(src, dest, topic, message)
end


return _M
