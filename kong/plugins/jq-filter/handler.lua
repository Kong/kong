local cjson = require "cjson.safe"
local cjson_decode = cjson.decode

local type, pairs, ipairs = type, pairs, ipairs
local str_find = string.find

local kong = kong

local CACHE


local JqFilter = {
  VERSION = "0.0.1",
  PRIORITY = 811,
}


function JqFilter:init_worker()
  CACHE = require "kong.plugins.jq-filter.cache"
end


local function is_media_type_allowed(content_type, filter_conf)
  local media_types = filter_conf.if_media_type
  for _, media_type in ipairs(media_types) do
    if str_find(content_type, media_type, 1, true) ~= nil then
      return true
    end
  end

  return false
end


function JqFilter:access(conf)
  local request_body = kong.request.get_raw_body()
  if not request_body then
    return
  end

  local new_headers = {}

  local request_content_type = kong.request.get_header("Content-Type")

  for _, filter in ipairs(conf.filters) do
    if filter.context ~= "request" or
      not is_media_type_allowed(request_content_type, filter) then

      goto next
    end

    local res = CACHE(
      filter.program,
      request_body,
      filter.jq_options
    )

    if filter.target == "body" then
      request_body = res

    elseif filter.target == "headers" then
      local headers = cjson_decode(res)

      if type(headers) == "table" then
        for name, value in pairs(headers or {}) do
          if type(name) == "string" and type(value) == "string" then
            new_headers[name] = value
          end
        end
      end
    end

    ::next::
  end

  kong.service.request.set_headers(new_headers)
  kong.service.request.set_raw_body(request_body)
end


return JqFilter
