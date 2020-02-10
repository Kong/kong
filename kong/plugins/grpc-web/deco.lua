-- Copyright (c) Kong Inc. 2020

local ffi = require "ffi"
local cjson = require "cjson"
local protoc = require "protoc"
local pb = require "pb"

local setmetatable = setmetatable
local ffi_cast = ffi.cast
local ffi_string = ffi.string

local ngx = ngx
local decode_base64 = ngx.decode_base64
local encode_base64 = ngx.encode_base64

local encode_json = cjson.encode
local decode_json = cjson.decode

local deco = {}
deco.__index = deco

ffi.cdef [[
  typedef struct __attribute__ ((__packed__)) frame_hdr {
    uint8_t frametype;
    uint32_t be_framesize;
  } frame_hdr;
]]

local frame_hdr = ffi.typeof("frame_hdr")
local frame_hdr_p = ffi.typeof("const frame_hdr *")
local HEADER_SIZE = ffi.sizeof("frame_hdr")


local text_encoding_from_mime = {
  ["application/grpc-web"] = "plain",
  ["application/grpc-web-text"] = "base64",
  ["application/grpc-web+proto"] = "plain",
  ["application/grpc-web-text+proto"] = "base64",
  ["application/grpc-web+json"] = "plain",
  ["application/grpc-web-text+json"] = "base64",
  ["application/json"] = "plain",
}

local framing_form_mime = {
  ["application/grpc-web"] = "grpc",
  ["application/grpc-web-text"] = "grpc",
  ["application/grpc-web+proto"] = "grpc",
  ["application/grpc-web-text+proto"] = "grpc",
  ["application/grpc-web+json"] = "grpc",
  ["application/grpc-web-text+json"] = "grpc",
  ["application/json"] = "none",
}

local msg_encodign_from_mime = {
  ["application/grpc-web"] = "proto",
  ["application/grpc-web-text"] = "proto",
  ["application/grpc-web+proto"] = "proto",
  ["application/grpc-web-text+proto"] = "proto",
  ["application/grpc-web+json"] = "json",
  ["application/grpc-web-text+json"] = "json",
  ["application/json"] = "json",
}



-- parse, compile and load .proto file
-- returns a table mapping valid request URLs to input/output types
local _proto_info = {}
local function get_proto_info(fname)
  local info = _proto_info[fname]
  if info then
    return info
  end

  local p = protoc.new()
  local parsed = p:parsefile(fname)

  info = {}

  for _, srvc in ipairs(parsed.service) do
    for _, mthd in ipairs(srvc.method) do
      info[("/%s.%s/%s"):format(parsed.package, srvc.name, mthd.name)] = {
        mthd.input_type,
        mthd.output_type,
      }
    end
  end

  _proto_info[fname] = info

  p:loadfile(fname)
  return info
end

-- return input and output names of the method specified by the url path
-- TODO: memoize
local function rpc_types(path, protofile)
  if not protofile then
    return nil
  end

  local info = get_proto_info(protofile)
  local types = info[path]
  if not types then
    return nil, ("Unkown path %q"):format(path)
  end

  return types[1], types[2]
end


function deco.new(mimetype, path, protofile)
  local text_encoding = text_encoding_from_mime[mimetype]
  local framing = framing_form_mime[mimetype]
  local msg_encoding = msg_encodign_from_mime[mimetype]

  local input_type, output_type
  if msg_encoding ~= "proto" then
    if not protofile then
      return nil, "transcoding requests require a .proto file defining the service"
    end

    input_type, output_type = rpc_types(path, protofile)
    if not input_type then
      return nil, output_type
    end
  end

  return setmetatable({
    mimetype = mimetype,
    text_encoding = text_encoding,
    framing = framing,
    msg_encoding = msg_encoding,
    input_type = input_type,
    output_type = output_type,
  }, deco)
end


local f_hdr = frame_hdr()
local function frame(ftype, msg)
  f_hdr.frametype = ftype
  f_hdr.be_framesize = bit.bswap(#msg)
  return ffi_string(f_hdr, HEADER_SIZE) .. msg
end

local function unframe(body)
  if not body or #body <= HEADER_SIZE then
    return nil, body
  end

  local hdr = ffi_cast(frame_hdr_p, body)
  local sz = bit.bswap(hdr.be_framesize)

  local frame_end = HEADER_SIZE + sz
  if frame_end > #body then
    return nil, body

  elseif frame_end == #body then
    return body:sub(HEADER_SIZE + 1)
  end

  return body:sub(HEADER_SIZE + 1, frame_end), body:sub(frame_end + 1)
end


function deco:upstream(body)
  if self.text_encoding == "base64" then
    body = decode_base64(body)
  end

  if self.msg_encoding == "json" then
    local msg = body
    if self.framing == "grpc" then
      msg = unframe(body)
    end

    body = frame(0x0, pb.encode(self.input_type, decode_json(msg)))
  end

  return body
end


function deco:downstream(chunk)
  if self.msg_encoding ~= "proto" then
    local body = (self.downstream_body or "") .. chunk

    local out, n = {}, 1
    local msg, body = unframe(body)

    while msg do
      msg = encode_json(pb.decode(self.output_type, msg))
      if self.framing == "grpc" then
        msg = frame(0x0, msg)
      end

      out[n] = msg
      n = n + 1
      msg, body = unframe(body)
    end

    self.downstream_body = body
    chunk = table.concat(out)
  end

  if self.text_encoding == "base64" then
    chunk = encode_base64(chunk)
  end

  return chunk
end


function deco:frame(ftype, msg)
  local f = frame(ftype, msg)

  if self.text_encoding == "base64" then
    f = ngx.encode_base64(f)
  end

  return f
end


return deco
