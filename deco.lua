-- Copyright (c) Kong Inc. 2020

local ffi = require "ffi"
local cjson = require "cjson"
local protoc = require "protoc"
local pb = require "pb"

local ngx = ngx
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
-- returns the parsed info as a table
local _proto_info = {}
local function get_proto_info(fname)
  local info = _proto_info[fname]
  if info then
    return info
  end

  local p = protoc.new()
  info = p:parsefile(fname)
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
  local pkg_name, service_name, method_name = path:match("^/([%w_]+)%.([%w_]+)/([%w_]+)")
  if not pkg_name then
    return nil, "malformed gRPC request path"
  end

  if pkg_name ~= info.package then
    return nil, string.format("unknown package %q, expecting %q", pkg_name, info.package)
  end

  for _, srvc in ipairs(info.service) do
    if srvc.name == service_name then
      for _, mthd in ipairs(srvc.method) do
        if mthd.name == method_name then
          return mthd.input_type, mthd.output_type
        end
      end
      return nil, string.format("method %q not found in service %q", method_name, service_name)
    end
  end
  return nil, string.format("service %q not found in package %q", service_name, pkg_name)
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
    if input_type == nil and output_type ~= nil then
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


local function frame(ftype, msg)
  local f_hdr = ffi.new(frame_hdr, ftype, bit.bswap(#msg))
  return ffi.string(f_hdr, ffi.sizeof(f_hdr)) .. msg
end

local function unframe(body)
  if not body then
    return
  end

  local hdr = ffi.cast(frame_hdr_p, body)
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
    body = ngx.decode_base64(body)
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
    chunk = ngx.encode_base64(chunk)
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
