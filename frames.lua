
local ffi = require "ffi"
local bit = require "bit"

local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64

ffi.cdef [[
  typedef struct __attribute__ ((__packed__)) frame_hdr {
    uint8_t frametype;
    uint32_t be_framesize;
  } frame_hdr;
]]

local frames = {}
frames.__index = frames


local frame_hdr = ffi.typeof("frame_hdr")
local frame_hdr_p = ffi.typeof("frame_hdr *")


function frames.new(mimetype, body)
  local text_based = mimetype == "application/grpc-web-text" or mimetype == "application/grpc-web-text+proto"

  if text_based then
    body = decode_base64(body)
  end

  return setmetatable({
    mimetype = mimetype,
    text_based = text_based,
    body = body,
    offset = 0,   -- zero based
  }, frames)
end


local frametype = {
  [0x00] = "pb",
  [0x80] = "trailer",
  -- TODO: 0x81=compressed"trailer"
}

local function do_iter(self)
  if self.offset >= #self.body then
    return nil
  end

  local p = ffi.cast('uint8_t*', self.body)
  p = p + self.offset
  local hdr = ffi.cast(frame_hdr_p, p)
  local sz = bit.bswap(hdr.be_framesize)
  if sz >= #self.body - self.offset then
    return nil
  end

  local prefixed_frame = self.body:sub(self.offset + 1, self.offset + sz + 5)
  self.offset = self.offset + sz + 6

  -- TODO: handle compressed frames

  return frametype[hdr.frametype], prefixed_frame
end


function frames:iter()
  return do_iter, self
end


function frames:encode(str)
  if self.text_based then
    str = encode_base64(str)
  end

  return str
end

function frames:frame(ftype, msg)
  local f_hdr = ffi.new(frame_hdr, ftype, bit.bswap(#msg))
  local frame = ffi.string(f_hdr, ffi.sizeof(f_hdr)) .. msg

  return self:encode(frame)
end


return frames
