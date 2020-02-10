-- Copyright (c) Kong Inc. 2020

local deco = require "kong.plugins.grpc-web.deco"

local ngx = ngx
local kong = kong

local string_format = string.format
local ngx_req_get_method = ngx.req.get_method
local kong_request_get_path = kong.request.get_path
local kong_request_get_header = kong.request.get_header
local kong_request_get_raw_body = kong.request.get_raw_body
local kong_response_exit = kong.response.exit
local kong_response_set_header = kong.response.set_header
local kong_service_request_set_header = kong.service.request.set_header
local kong_service_request_set_raw_body = kong.service.request.set_raw_body


local grpc_web = {
  PRIORITY = 1,
  VERSION = '0.1.0',
}


function grpc_web:access(conf)
  kong_response_set_header("Access-Control-Allow-Origin", "*")

  if ngx_req_get_method() == "OPTIONS" then
    return kong_response_exit(200, "OK", {
      ["Content-Type"] = "application/grpc-web-text+proto",
      ["Access-Control-Allow-Origin"] = "*",
      ["Access-Control-Allow-Methods"] = "POST",
      ["Access-Control-Allow-Headers"] = "content-type,x-grpc-web,x-user-agent",
    })
  end


  local dec, err = deco.new(
    kong_request_get_header("Content-Type"),
    kong_request_get_path(), conf.proto)

  if not dec then
    kong.log.err(err)
    return kong_response_exit(500, err, {})
  end

  kong.ctx.plugin.dec = dec

  kong_service_request_set_header("Content-Type", "application/grpc")
  kong_service_request_set_header("TE", "trailers")
  kong_service_request_set_raw_body(dec:upstream(kong_request_get_raw_body()))
end


function grpc_web:header_filter(conf)
  if ngx_req_get_method() == "OPTIONS" then
    return
  end

  local dec = kong.ctx.plugin.dec
  if dec then
    kong_response_set_header("Content-Type", dec.mimetype)
  end
end


function grpc_web:body_filter(conf)
  if ngx_req_get_method() ~= "POST" then
    return
  end
  local dec = kong.ctx.plugin.dec
  if not dec then
    return
  end

  local chunk, eof = ngx.arg[1], ngx.arg[2]

  chunk = dec:downstream(chunk)

  if eof and dec.framing == "grpc" then
    chunk = chunk .. dec:frame(0x80, string_format(
      "grpc-status:%s\r\ngrpc-message:%s\r\n",
      ngx.var["sent_trailer_grpc_status"] or "0",
      ngx.var["sent_trailer_grpc_message"] or ""))
  end

  ngx.arg[1] = chunk
end


return grpc_web
