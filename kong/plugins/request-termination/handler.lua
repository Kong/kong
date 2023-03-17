-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local kong_meta = require "kong.meta"

local DEFAULT_RESPONSE = {
  [401] = "Unauthorized",
  [404] = "Not found",
  [405] = "Method not allowed",
  [500] = "An unexpected error occurred",
  [502] = "Bad Gateway",
  [503] = "Service unavailable",
}


local RequestTerminationHandler = {}


RequestTerminationHandler.PRIORITY = 2
RequestTerminationHandler.VERSION = kong_meta.core_version


function RequestTerminationHandler:access(conf)
  local status  = conf.status_code
  local content = conf.body
  local req_headers, req_query

  if conf.trigger or conf.echo then
    req_headers = kong.request.get_headers()
    req_query = kong.request.get_query()

    if conf.trigger
       and not req_headers[conf.trigger]
       and not req_query[conf.trigger] then
      return -- trigger set but not found, nothing to do
    end
  end

  if conf.echo then
    content = {
      message = conf.message or DEFAULT_RESPONSE[status],
      kong = {
        node_id = kong.node.get_id(),
        worker_pid = ngx.worker.pid(),
        hostname = kong.node.get_hostname(),
      },
      request = {
        scheme = kong.request.get_scheme(),
        host = kong.request.get_host(),
        port = kong.request.get_port(),
        headers = req_headers,
        query = req_query,
        body = kong.request.get_body(),
        raw_body = kong.request.get_raw_body(),
        method = kong.request.get_method(),
        path = kong.request.get_path(),
        uri_captures = kong.request.get_uri_captures(),
      },
      matched_route = kong.router.get_route(),
      matched_service = kong.router.get_service(),
    }

    return kong.response.exit(status, content)
  end

  if content then
    local headers = {
      ["Content-Type"] = conf.content_type
    }

    return kong.response.exit(status, content, headers)
  end

  local message = conf.message or DEFAULT_RESPONSE[status]
  return kong.response.exit(status, message and { message = message } or nil)
end


return RequestTerminationHandler
