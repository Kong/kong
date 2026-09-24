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
-- if stream_parser:has_complete_message() then
--   local next, err = stream_parser:next_message()
--   -- do something with the next message
-- end
function Stream:new(chunk, is_hex)
  local self = {}  -- override 'self' to be the new object/class
  setmetatable(self, Stream)

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
  if #bytes < count * 2 then
    return nil, "not enough bytes in buffer when trying to read " .. count .. " bytes, only " .. #bytes / 2 .. " bytes available"
  end
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

  local int, err = self:next_bytes(size / 8)
  if err then
    return nil, nil, err
  end

  return tonumber(int, 16), int
end

--- Extract a single header from the stream
-- @return table|nil header containing key and value, or nil on error
-- @return number bytes consumed for this header
-- @return string error message if failed
function Stream:extract_header()
  -- the next 8-bit int is the "header key length"
  local header_key_len, _, err = self:next_int(8)
  if err then
    return nil, 0, "failed to read header key length: " .. err
  end

  -- Validate header key length
  if header_key_len < 1 or header_key_len > 255 then
    return nil, 0, "invalid header key length: " .. tostring(header_key_len)
  end

  local header_key = self:next_utf_8(header_key_len)
  if not header_key then
    return nil, 0, "failed to read header key"
  end

  local bytes_consumed = 1 + header_key_len  -- key length byte + key bytes

  -- next 8-bits is the header type, which is an enum
  local header_type, _, err = self:next_int(8)
  if err then
    return nil, bytes_consumed, "failed to read header type: " .. err
  end

  bytes_consumed = bytes_consumed + 1  -- header type byte

  -- Validate header type is in valid range (0-9 according to AWS spec)
  if header_type < 0 or header_type > 9 then
    return nil, bytes_consumed, "invalid header type: " .. tostring(header_type)
  end

  -- depending on the header type, depends on how long the header should max out at
  local extractor = _HEADER_EXTRACTORS[header_type]
  if not extractor then
    return nil, bytes_consumed, "unsupported header type: " .. tostring(header_type)
  end

  local header_value, header_value_len = extractor(self)
  if not header_value then
    return nil, bytes_consumed, "failed to extract header value for type: " .. tostring(header_type)
  end

  bytes_consumed = bytes_consumed + header_value_len

  return {
    key = header_key,
    value = header_value,
    type = header_type
  }, bytes_consumed, nil
end

--- returns the length of the chunk in bytes
-- @return number length of the chunk in bytes
function Stream:bytes()
  if not self.chunk then
    return nil, "function cannot be called on its own - initialise a chunk reader with :new(chunk)"
  end

  -- because the chunk is hex-encoded, we divide by 2 to get the actual byte count
  return #self.chunk / 2
end

local function hex_char_to_int(c)
  -- The caller should ensure that `c` is a valid hex character
  if c < 58 then
    c = c - 48  -- '0' to '9'
  else
    c = c - 87  -- 'a' to 'f'
  end
  return tonumber(c)
end

function Stream:has_complete_message()
  if not self.chunk then
    return nil, "function cannot be called on its own - initialise a chunk reader with :new(chunk)"
  end

  local n = self:bytes()
  -- check if we have at least the 4 bytes for the message length
  if n < 4 then
    return false
  end

  local ptr, _ = self.chunk:ref()
  local msg_len = 0
  for i = 0, 3 do
    msg_len = msg_len * 256 + hex_char_to_int(ptr[i * 2]) * 16 + hex_char_to_int(ptr[i * 2 + 1])
  end
  return n >= msg_len
end

function Stream:add(chunk, is_hex)
  if not self.chunk then
    return nil, "function cannot be called on its own - initialise a chunk reader with :new(chunk)"
  end

  if type(chunk) ~= "string" then
    return nil, "data must be a string"
  end

  -- add the data to the chunk
  self.chunk:put((is_hex and chunk) or to_hex(chunk))
end

--- returns the next message in the chunk, as a table.
--- can be used as an iterator.
-- @return table formatted next message from the given constructor chunk 
function Stream:next_message()
  if not self.chunk then
    return nil, "function cannot be called on its own - initialise a chunk reader with :new(chunk)"
  end

  if not self:has_complete_message() then
    return nil, "not enough bytes in buffer for a complete message"
  end

  -- get the message length and pull that many bytes
  --
  -- this is a chicken and egg problem, because we need to
  -- read the message to get the length, to then re-read the
  -- whole message at correct offset
  local msg_len, _, err = self:next_int(32)
  if err then
    return nil, err
  end
  
  -- get the headers length
  local headers_len, _, err = self:next_int(32)
  if err then
    return nil, err
  end

  -- get the preamble checksum
  -- skip it because we're not using UDP
  self:next_int(32)

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
  -- skip it because we're not using UDP
  self:next_int(32)


  -- rewind the tape
  self.read_count = 0

  return {
    headers = headers,
    body = body,
  }
end

return Stream