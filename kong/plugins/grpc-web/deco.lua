-- Copyright (c) Kong Inc. 2020

local cjson = require "cjson"
local pb = require "pb"
local grpc_tools = require "kong.tools.grpc"
local grpc_frame = grpc_tools.frame
local grpc_unframe = grpc_tools.unframe

local setmetatable = setmetatable

local ngx = ngx
local decode_base64 = ngx.decode_base64
local encode_base64 = ngx.encode_base64

local encode_json = cjson.encode
local decode_json = cjson.decode

local deco = {}
deco.__index = deco


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

  info = {}
  local grpc_tools_instance = grpc_tools.new()
  grpc_tools_instance:each_method(fname, function(parsed, srvc, mthd)
    info[("/%s.%s/%s"):format(parsed.package, srvc.name, mthd.name)] = {
      mthd.input_type,
      mthd.output_type,
    }
  end, true)

  _proto_info[fname] = info
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


function deco:upstream(body)
  if self.text_encoding == "base64" then
    body = decode_base64(body)
  end

  if self.msg_encoding == "json" then
    local msg = body
    if self.framing == "grpc" then
      msg = grpc_unframe(body)
    end

    body = grpc_frame(0x0, pb.encode(self.input_type, decode_json(msg)))
  end

  return body
end


function deco:downstream(chunk)
  if self.msg_encoding ~= "proto" then
    local body = (self.downstream_body or "") .. chunk

    local out, n = {}, 1
    local msg, body = grpc_unframe(body)

    while msg do
      msg = encode_json(pb.decode(self.output_type, msg))
      if self.framing == "grpc" then
        msg = grpc_frame(0x0, msg)
      end

      out[n] = msg
      n = n + 1
      msg, body = grpc_unframe(body)
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
  local f = grpc_frame(ftype, msg)

  if self.text_encoding == "base64" then
    f = ngx.encode_base64(f)
  end

  return f
end


return deco
