-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local parse_directive_header = require("kong.tools.http").parse_directive_header
local calculate_resource_ttl = require("kong.tools.http").calculate_resource_ttl


local _M = {
  NAME = "ai-semantic-cache-response-cc-header",
  STAGE = "RES_INTROSPECTION",
  DESCRIPTION = "send appropriate Cache-Control header in response, if there's no cache hit",
}

-- Retrieves response Cache-Control directives
local function res_cc()
  return parse_directive_header(ngx.var.sent_http_cache_control)
end

-- Checks if the response is cacheable based on Cache-Control directives
local function cacheable_response(conf, cc)
  if conf.cache_control and (cc["private"] or cc["no-store"] or cc["no-cache"]) then
    return false
  end

  if conf.cache_control and calculate_resource_ttl(cc) <= 0 then
    return false
  end

  return true
end

function _M:run(conf)
  local cc = res_cc()

  if not cacheable_response(conf, cc) then
    kong.response.set_header("X-Cache-Status", "Bypass")
  end

  return true
end

return _M