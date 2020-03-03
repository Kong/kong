-- Copyright (c) Kong Inc. 2020

local deco = require "kong.plugins.grpc-gateway.deco"

local ngx = ngx
local kong = kong

local string_format = string.format

local ngx_arg = ngx.arg
local ngx_var = ngx.var

local kong_request_get_path = kong.request.get_path
local kong_request_get_method = kong.request.get_method
local kong_request_get_raw_body = kong.request.get_raw_body
local kong_response_exit = kong.response.exit
local kong_response_set_header = kong.response.set_header
local kong_service_request_set_header = kong.service.request.set_header
local kong_service_request_set_path = kong.service.request.set_path
local kong_service_request_set_method = kong.service.request.set_method
local kong_service_request_set_raw_body = kong.service.request.set_raw_body


local grpc_gateway = {
  PRIORITY = 3,
  VERSION = '0.1.0',
}

--require "lua_pack"


local CORS_HEADERS = {
  ["Content-Type"] = "application/json",
  ["Access-Control-Allow-Origin"] = "*",
  ["Access-Control-Allow-Methods"] = "GET,POST,PATCH,DELETE",
  ["Access-Control-Allow-Headers"] = "content-type", -- TODO: more headers?
}

function grpc_gateway:access(conf)
  kong_response_set_header("Access-Control-Allow-Origin", "*")

  if kong_request_get_method() == "OPTIONS" then
    return kong_response_exit(200, "OK", CORS_HEADERS)
  end


  local dec, err = deco.new(kong_request_get_method():lower(),
                            kong_request_get_path(), conf.proto)

  if not dec then
    kong.log.err(err)
    return kong_response_exit(400, err)
  end

  kong.ctx.plugin.dec = dec

  kong_service_request_set_header("Content-Type", "application/grpc")
  kong_service_request_set_header("TE", "trailers")
  kong_service_request_set_raw_body(dec:upstream(kong_request_get_raw_body()))

  ngx.req.set_uri(dec.rewrite_path)
  -- kong_service_request_set_method("POST")
end


function grpc_gateway:header_filter(conf)
  if kong_request_get_method() == "OPTIONS" then
    return
  end

  local dec = kong.ctx.plugin.dec
  if dec then
    kong_response_set_header("Content-Type", "application/json")
  end
end


function grpc_gateway:body_filter(conf)
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


return grpc_gateway