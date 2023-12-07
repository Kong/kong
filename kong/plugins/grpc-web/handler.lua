-- Copyright (c) Kong Inc. 2020

local deco = require "kong.plugins.grpc-web.deco"
local kong_meta = require "kong.meta"

local ngx = ngx
local kong = kong

local string_format = string.format
local io_open = io.open

local ngx_arg = ngx.arg
local ngx_var = ngx.var

local kong_request_get_path = kong.request.get_path
local kong_request_get_header = kong.request.get_header
local kong_request_get_method = kong.request.get_method
local kong_request_get_raw_body = kong.request.get_raw_body
local ngx_req_get_body_file = ngx.req.get_body_file
local kong_response_exit = kong.response.exit
local kong_response_set_header = kong.response.set_header
local kong_service_request_set_header = kong.service.request.set_header
local kong_service_request_set_raw_body = kong.service.request.set_raw_body
local warn = kong.log.warn


local grpc_web = {
  PRIORITY = 3,
  VERSION = kong_meta.version,
}


local CORS_HEADERS = {
  ["Content-Type"] = "application/grpc-web-text+proto",
  ["Access-Control-Allow-Origin"] = "*",
  ["Access-Control-Allow-Methods"] = "POST",
  ["Access-Control-Allow-Headers"] = "content-type,x-grpc-web,x-user-agent",
}

local function get_body()
  local body, err = kong_request_get_raw_body()
  if body then
    return body
  end

  -- if body_file is not nil, the error of get_raw_body is expected
  -- otherwise return the error
  local body_file = ngx_req_get_body_file()
  assert(body_file, err)

  warn("client_body_buffer_size exceeded and reading the request from disk. Please consider increasing the value.")

  local file = assert(io_open(body_file, "rb"))
  body = assert(file:read("*a"))
  file:close()

  return body
end

function grpc_web:access(conf)
  kong_response_set_header("Access-Control-Allow-Origin", conf.allow_origin_header)

  if kong_request_get_method() == "OPTIONS" then
    CORS_HEADERS["Access-Control-Allow-Origin"] = conf.allow_origin_header
    return kong_response_exit(200, "OK", CORS_HEADERS)
  end

  local uri
  if conf.pass_stripped_path then
    uri = ngx_var.upstream_uri
    ngx.req.set_uri(uri)
  else
    uri = kong_request_get_path()
  end

  local dec, err = deco.new(
    kong_request_get_header("Content-Type"),
    uri, conf.proto)

  if not dec then
    kong.log.err(err)
    return kong_response_exit(400, err)
  end

  kong.ctx.plugin.dec = dec

  kong_service_request_set_header("Content-Type", "application/grpc")
  kong_service_request_set_header("TE", "trailers")
  kong_service_request_set_raw_body(dec:upstream(get_body()))
end


function grpc_web:header_filter(conf)
  if kong_request_get_method() == "OPTIONS" then
    return
  end

  local dec = kong.ctx.plugin.dec
  if dec then
    kong_response_set_header("Content-Type", dec.mimetype)
  end
end


function grpc_web:body_filter(conf)
  if kong_request_get_method() ~= "POST" then
    return
  end
  local dec = kong.ctx.plugin.dec
  if not dec then
    return
  end

  local chunk, eof = ngx_arg[1], ngx_arg[2]

  chunk = dec:downstream(chunk)

  if eof and dec.framing == "grpc" then
    chunk = chunk .. dec:frame(0x80, string_format(
      "grpc-status:%s\r\ngrpc-message:%s\r\n",
      ngx_var["sent_trailer_grpc_status"] or "0",
      ngx_var["sent_trailer_grpc_message"] or ""))
  end

  ngx_arg[1] = chunk
end


return grpc_web
