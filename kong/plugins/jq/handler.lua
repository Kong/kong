local cjson = require "cjson.safe"
local cjson_decode = cjson.decode

local inflate_gzip = require("kong.tools.utils").inflate_gzip

local type, pairs, ipairs = type, pairs, ipairs
local str_find = string.find

local kong = kong

local CACHE = require "kong.plugins.jq.cache"


local Jq = {
  VERSION = "0.0.1",
  PRIORITY = 811,
}


local function is_media_type_allowed(content_type, filter_conf)
  if type(content_type) ~= "string" then
    return false
  end

  local media_types = filter_conf.if_media_type
  for _, media_type in ipairs(media_types) do
    if str_find(content_type, media_type, 1, true) ~= nil then
      return true
    end
  end

  return false
end


local function is_status_code_allowed(status_code, filter_conf)
  local status_codes = filter_conf.if_status_code
  for _, code in ipairs(status_codes) do
    if status_code == code then
      return true
    end
  end

  return false
end


--- Runs a given jq program.
-- Programs are compiled and stored in a module level cache, since compilation
-- can be expensive.
local function run_program(program, data, options)
  local jqp, err = CACHE(program)
  if not jqp then
    return nil, err
  end

  local output, err = jqp:filter(data, options)
  if not output then
    return nil, err
  end

  return output
end


--- Processes the filter.
-- The `data` table is both an in and out parameter. It should have two fields,
-- `body` and `extra_headers`. The `body` is used as the filter source in all
-- cases, but also may be updated by the filter, in the case of filters whose
-- target is `body`.
--
-- Since multiple filters may be run, this data structure is updated in place
-- until all are completed for the phase.
local function process_filter(data, filter)
  local output, err = run_program(
    filter.program,
    data.body,
    filter.jq_options
  )

  if not output then
    return nil, err
  end

  if filter.target == "body" then
    data.body = output

  elseif filter.target == "headers" then
    local headers = cjson_decode(output)

    if type(headers) == "table" then
      for name, value in pairs(headers) do
        if type(name) == "string" and type(value) == "string" then
          data.extra_headers[name] = value
        end
      end
    end
  end

  return true
end


-- Runs each filter with a `context` of `request`, and updates the request
-- headers and / or body accordingly.
function Jq:access(conf)
  local request_body = kong.request.get_raw_body()
  if not request_body then
    return
  end

  if kong.request.get_header("Content-Encoding") == "gzip" then
    request_body = inflate_gzip(request_body)
  end

  local results = {
    body = request_body,
    extra_headers = {}
  }

  local request_content_type = kong.request.get_header("Content-Type")

  for _, filter in ipairs(conf.filters) do
    if filter.context == "request" and
      is_media_type_allowed(request_content_type, filter) then

      local ok, err = process_filter(results, filter)
      if not ok then
        kong.log.err(err)
      end
    end
  end

  kong.service.request.set_headers(results.extra_headers)
  kong.service.request.set_raw_body(results.body)
end


-- Runs each filter with a `context` of `response`, and updates the response
-- headers and / or body accordingly.
--
-- Note: we call `kong.response.exit` and so this will be the last plugin to
-- run for this phase.
function Jq:response(conf)
  local response_body = kong.service.response.get_raw_body()
  if not response_body then
    return
  end

  if kong.response.get_header("Content-Encoding") == "gzip" then
    response_body = inflate_gzip(response_body)
    kong.response.clear_header("Content-Encoding")
  end

  local results = {
    body = response_body,
    extra_headers = {}
  }

  local response_status = kong.response.get_status()
  local response_content_type = kong.response.get_header("Content-Type")

  for _, filter in ipairs(conf.filters) do
    if filter.context == "response" and
      is_media_type_allowed(response_content_type, filter) and
      is_status_code_allowed(response_status, filter) then

      local ok, err = process_filter(results, filter)
      if not ok then
        kong.log.err(err)
      end
    end
  end

  kong.response.set_headers(results.extra_headers)
  return kong.response.exit(response_status, results.body)
end


return Jq
