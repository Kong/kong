-- Copyright (c) Kong Inc. 2020

local to_hex = require "resty.string".to_hex
local frames = require "kong.plugins.grpc-web.frames"

local ngx = ngx
local kong = kong

local string_format = string.format
local ngx_req_get_method = ngx.req.get_method
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
--   kong.log.debug("access method: ", ngx.req.get_method())
  kong_response_set_header("Access-Control-Allow-Origin", "*")

  if ngx_req_get_method() == "OPTIONS" then
    return kong_response_exit(200, "OK", {
      ["Content-Type"] = "application/grpc-web-text+proto",
      ["Access-Control-Allow-Origin"] = "*",
      ["Access-Control-Allow-Methods"] = "POST",
      ["Access-Control-Allow-Headers"] = "content-type,x-grpc-web,x-user-agent",
    })
  end

  local body_frames = frames.new(
      kong_request_get_header("Content-Type"),
      kong_request_get_raw_body())

  kong.ctx.plugin.framer = body_frames

  local new_req, n = {}, 0

  for msg_type, msg in body_frames:iter() do
    if msg_type == "pb" then
      n = n + 1
      new_req[n] = msg

    elseif msg_type == "trailer" then
      kong.log.debug("trailer: ", to_hex(msg))
      -- add to headers? hope they get into trailers?
    end
  end

  kong_service_request_set_header("Content-Type", "application/grpc")
  kong_service_request_set_header("TE", "trailers")
  kong_service_request_set_raw_body(table.concat(new_req))
end


function grpc_web:header_filter(conf)
  if ngx_req_get_method() == "OPTIONS" then
    return
  end

  kong_response_set_header("Content-Type", kong.ctx.plugin.framer.mimetype)
end

function grpc_web:body_filter(conf)
  if ngx_req_get_method() ~= "POST" then
    return
  end

  local chunk, eof = ngx.arg[1], ngx.arg[2]

  local framer = kong.ctx.plugin.framer
  chunk = framer:encode(chunk)

  if eof then
    chunk = chunk .. framer:frame(0x80, string_format(
      "grpc-status:%s\r\ngrpc-message:%s\r\n",
      ngx.var["sent_trailer_grpc_status"] or "0",
      ngx.var["sent_trailer_grpc_message"] or ""))
  end

  ngx.arg[1] = chunk
end


return grpc_web
