-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local stringy = require "stringy"

local RequestSizeLimitingHandler = BasePlugin:extend()

RequestSizeLimitingHandler.PRIORITY = 950

local function check_size(length, allowed_size, headers)
  local allowed_bytes_size = allowed_size * 100000
  if length > allowed_bytes_size then
    if headers.expect and stringy.strip(headers.expect:lower()) == "100-continue" then
      return responses.send(417, "Request size limit exceeded")
    else
      return responses.send(413, "Request size limit exceeded")
    end
  end
end

function RequestSizeLimitingHandler:new()
  RequestSizeLimitingHandler.super.new(self, "request-size-limiting")
end

function RequestSizeLimitingHandler:access(conf)
  RequestSizeLimitingHandler.super.access(self)
  local headers = ngx.req.get_headers()
  if headers["content-length"] then
    check_size(tonumber(headers["content-length"]), conf.allowed_payload_size, headers)
  else
    -- If the request body is too big, this could consume too much memory (to check)
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    if data then
      check_size(string.len(data), conf.allowed_payload_size, headers)
    end
  end
end

return RequestSizeLimitingHandler
