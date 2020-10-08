local kong = kong
local string = string


local CACHE


local JqRequestFilter = {
  VERSION = "0.0.1",
  PRIORITY = 811,
}


function JqRequestFilter:init_worker()
  CACHE = require "kong.plugins.jq-request-filter.cache"
end


function JqRequestFilter:access(conf)
  local request_body = kong.request.get_raw_body()
  if not request_body then
    return
  end

  local request_content_type = kong.request.get_header("Content-Type")
  local content_type

  local count = #conf.filters
  for i = 1, count do
    local mime_in = conf.filters[i].mime["in"]
    if mime_in and string.find(request_content_type, mime_in) ~= 1 then
      goto next
    end

    local mime_out = conf.filters[i].mime.out
    if mime_out then
      content_type = mime_out
    end

    request_body = CACHE(conf.filters[i].program, request_body, conf.filters[i].opts)

    ::next::
  end

  if content_type and content_type ~= request_content_type then
    kong.service.request.set_header("Content-Type", content_type)
  end

  kong.service.request.set_raw_body(request_body)
end


return JqRequestFilter
