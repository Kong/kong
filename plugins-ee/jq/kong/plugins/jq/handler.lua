-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local inflate_gzip = require("kong.tools.gzip").inflate_gzip

local type, ipairs = type, ipairs
local str_find = string.find

local kong = kong
local meta = require "kong.meta"

local CACHE = require "kong.plugins.jq.cache"


local Jq = {
  VERSION = meta.core_version,
  PRIORITY = 811,
}


local function is_media_type_allowed(content_type, allowed_media_types)
  if type(content_type) ~= "string" then
    return false
  end

  for _, media_type in ipairs(allowed_media_types) do
    if str_find(content_type, media_type, 1, true) ~= nil then
      return true
    end
  end

  return false
end


local function is_status_code_allowed(status_code, allowed_status_codes)
  for _, code in ipairs(allowed_status_codes) do
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


function Jq:access(conf)
  if type(conf.request_jq_program) == "string" and
    is_media_type_allowed(kong.request.get_header("Content-Type"),
                          conf.request_if_media_type) then

    local request_body = kong.request.get_raw_body()
    if not request_body then
      return
    end

    if kong.request.get_header("Content-Encoding") == "gzip" then
      request_body = inflate_gzip(request_body)
    end

    local jq_output, err = run_program(
      conf.request_jq_program,
      request_body,
      conf.request_jq_program_options
    )

    if not jq_output then
      kong.log.err(err)
    else
      kong.service.request.set_raw_body(jq_output)
    end
  end
end


--- Process the response headers.
--
-- Drops Content-Length and Content-Encoding (in the case of gzipped
-- responses) if we think the program is going to change the output.
--
-- Nginx should send with chunked transfer encoding instead.
function Jq:header_filter(conf)
  if type(conf.response_jq_program) == "string" and
    is_media_type_allowed(kong.response.get_header("Content-Type"),
                          conf.response_if_media_type) and
    is_status_code_allowed(kong.response.get_status(),
                           conf.response_if_status_code) then

    kong.response.clear_header("Content-Length")

    if kong.response.get_header("Content-Encoding") == "gzip" then
      kong.ctx.plugin.should_inflate_gzip = true
      kong.response.clear_header("Content-Encoding")
    end
  end
end


--- Processes the response body program.
--
-- Note: we buffer the entire response in order to feed valid JSON to jq.
function Jq:body_filter(conf)
  if type(conf.response_jq_program) == "string" and
    is_media_type_allowed(kong.response.get_header("Content-Type"),
                          conf.response_if_media_type) and
    is_status_code_allowed(kong.response.get_status(),
                           conf.response_if_status_code) then

    local response_body = kong.response.get_raw_body()

    if response_body then
      if kong.ctx.plugin.should_inflate_gzip then
        response_body = inflate_gzip(response_body)
      end

      local jq_output, err = run_program(
        conf.response_jq_program,
        response_body,
        conf.response_jq_program_options
      )

      if not jq_output then
        kong.log.err(err)
      else
        kong.response.set_raw_body(jq_output)
      end
    end
  end
end


return Jq
