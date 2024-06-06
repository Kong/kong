--- Stream class.
-- Decodes AWS response-stream types, currently application/vnd.amazon.eventstream
-- @classmod Stream

local buf = require("string.buffer")
local to_hex = require("resty.string").to_hex

local Stream = {}
Stream.__index = Stream


local _HEADER_EXTRACTORS = {
  -- bool true
  [0] = function(stream)
    return true, 0
  end,
  
  -- bool false
  [1] = function(stream)
    return false, 0
  end,

  -- string type
  [7] = function(stream)
    local header_value_len = stream:next_int(16)
    return stream:next_utf_8(header_value_len), header_value_len + 2  -- add the 2 bits read for the length
  end,

  -- TODO ADD THE REST OF THE DATA TYPES
  -- EVEN THOUGH THEY'RE NOT REALLY USED
}

--- Constructor.
-- @function aws:Stream
-- @param chunk string complete AWS response stream chunk for decoding
-- @param is_hex boolean specify if the chunk bytes are already decoded to hex
-- @usage
-- local stream_parser = stream:new("00000120af0310f.......", true)
-- local next, err = stream_parser:next_message()
function Stream:new(chunk, is_hex)
  local self = {}  -- override 'self' to be the new object/class
  setmetatable(self, Stream)
  
  if #chunk < ((is_hex and 32) or 16) then
    return nil, "cannot parse a chunk less than 16 bytes long"
  end
  
  self.read_count = 0  
  self.chunk = buf.new()
  self.chunk:put((is_hex and chunk) or to_hex(chunk))
  
  return self
end


--- return the next `count` ascii bytes from the front of the chunk
--- and then trims the chunk of those bytes
-- @param count number whole utf-8 bytes to return
-- @return string resulting utf-8 string
function Stream:next_utf_8(count)
  local utf_bytes = self:next_bytes(count)
  
  local ascii_string = ""
  for i = 1, #utf_bytes, 2 do
      local hex_byte = utf_bytes:sub(i, i + 1)
      local ascii_byte = string.char(tonumber(hex_byte, 16))
      ascii_string = ascii_string .. ascii_byte
  end
  return ascii_string
end

--- returns the next `count` bytes from the front of the chunk
--- and then trims the chunk of those bytes
-- @param count number whole integer of bytes to return
-- @return string hex-encoded next `count` bytes
function Stream:next_bytes(count)
  if not self.chunk then
    return nil, "function cannot be called on its own - initialise a chunk reader with :new(chunk)"
  end

  local bytes = self.chunk:get(count * 2)
  self.read_count = (count) + self.read_count

  return bytes
end

--- returns the next unsigned int from the front of the chunk
--- and then trims the chunk of those bytes
-- @param size integer bit length (8, 16, 32, etc)
-- @return number whole integer of size specified
-- @return string the original bytes, for reference/checksums
function Stream:next_int(size)
  if not self.chunk then
    return nil, nil, "function cannot be called on its own - initialise a chunk reader with :new(chunk)"
  end

  if size < 8 then
    return nil, nil, "cannot work on integers smaller than 8 bits long"
  end

  local int, err = self:next_bytes(size / 8, trim)
  if err then
    return nil, nil, err
  end

  return tonumber(int, 16), int
end

--- returns the next message in the chunk, as a table.
--- can be used as an iterator.
-- @return table formatted next message from the given constructor chunk 
function Stream:next_message()
  if not self.chunk then
    return nil, "function cannot be called on its own - initialise a chunk reader with :new(chunk)"
  end

  if #self.chunk < 1 then
    return false
  end

  -- get the message length and pull that many bytes
  --
  -- this is a chicken and egg problem, because we need to
  -- read the message to get the length, to then re-read the
  -- whole message at correct offset
  local msg_len, orig_len, err = self:next_int(32)
  if err then
    return err
  end
  
  -- get the headers length
  local headers_len, orig_headers_len, err = self:next_int(32)

  -- get the preamble checksum
  local preamble_checksum, orig_preamble_checksum, err = self:next_int(32)

  -- TODO: calculate checksum
  -- local result = crc32(orig_len .. origin_headers_len, preamble_checksum)
  -- if not result then
  --   return nil, "preamble checksum failed - message is corrupted"
  -- end

  -- pull the headers from the buf
  local headers = {}
  local headers_bytes_read = 0

  while headers_bytes_read < headers_len do
    -- the next 8-bit int is the "header key length"
    local header_key_len = self:next_int(8)
    local header_key = self:next_utf_8(header_key_len)
    headers_bytes_read = 1 + header_key_len + headers_bytes_read

    -- next 8-bits is the header type, which is an enum
    local header_type = self:next_int(8)
    headers_bytes_read = 1 + headers_bytes_read

    -- depending on the header type, depends on how long the header should max out at
    local header_value, header_value_len = _HEADER_EXTRACTORS[header_type](self)
    headers_bytes_read = header_value_len + headers_bytes_read

    headers[header_key] = header_value
  end

  -- finally, extract the body as a string by
  -- subtracting what's read so far from the
  -- total length obtained right at the start
  local body = self:next_utf_8(msg_len - self.read_count - 4)

  -- last 4 bytes is a body checksum
  local msg_checksum = self:next_int(32)
  -- TODO CHECK FULL MESSAGE CHECKSUM
  -- local result = crc32(original_full_msg, msg_checksum)
  -- if not result then
  --   return nil, "preamble checksum failed - message is corrupted"
  -- end

  -- rewind the tape
  self.read_count = 0

  return {
    headers = headers,
    body = body,
  }
end

return Stream
