local cjson = require "cjson.safe"


local kong = kong
local type = type
local pairs = pairs
local string = string


local CACHE
local HEADERS = {
  ["Content-Type"] = "",
}


local JqResponseFilter = {
  VERSION = "0.0.1",
  PRIORITY = 810,
}


function JqResponseFilter:init_worker()
  CACHE = require "kong.plugins.jq-request-filter.cache"
end


function JqResponseFilter:response(conf)
  local response_body = kong.service.response.get_raw_body()
  if not response_body then
    return
  end

  local response_status = kong.response.get_status()
  local response_content_type = kong.response.get_header("Content-Type")

  local content_type
  local status
  local headers

  local count = #conf.filters
  for i = 1, count do
    local status_in = conf.filters[i].status["in"]
    if status_in and status_in ~= response_status then
      goto next
    end

    local mime_in = conf.filters[i].mime["in"]
    if mime_in and string.find(response_content_type, mime_in) ~= 1 then
      goto next
    end

    local status_out = conf.filters[i].status.out
    if status_out then
      status = status_out
    end

    local mime_out = conf.filters[i].mime.out
    if mime_out then
      content_type = mime_out
    end

    if conf.filters[i].target == "body" then
      response_body = CACHE(conf.filters[i].program, response_body, conf.filters[i].opts)

    else
      local instructions = CACHE(conf.filters[i].program, response_body, conf.filters[i].opts)
      local hdrs = cjson.decode(instructions)
      if type(hdrs) == "table" then
        for name, value in pairs(hdrs) do
          if type(name) == "string" then
            if not headers then
              headers = {
                [name] = value
              }
            else
              headers[name] = value
            end
          end
        end
      end
    end

    ::next::
  end

  if content_type and content_type ~= response_content_type then
    if not headers then
      headers = HEADERS
    end
    headers["Content-Type"] = content_type
  end

  return kong.response.exit(status or response_status, response_body, headers)
end


return JqResponseFilter
