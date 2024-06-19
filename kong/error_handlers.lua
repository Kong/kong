local kong = kong
local find = string.find
local fmt  = string.format
local request_id = require "kong.observability.tracing.request_id"
local tools_http = require "kong.tools.http"


local CONTENT_TYPE    = "Content-Type"
local ACCEPT          = "Accept"
local TYPE_GRPC       = "application/grpc"


local BODIES = {
  [400] = "Bad request",
  [404] = "Not found",
  [405] = "Method not allowed",
  [408] = "Request timeout",
  [411] = "Length required",
  [412] = "Precondition failed",
  [413] = "Payload too large",
  [414] = "URI too long",
  [417] = "Expectation failed",
  [494] = "Request header or cookie too large",
  [500] = "An unexpected error occurred",
  [502] = "An invalid response was received from the upstream server",
  [503] = "The upstream server is currently unavailable",
  [504] = "The upstream server is timing out",
}


local get_body
do
  local DEFAULT_FMT = "The upstream server responded with %d"

  get_body = function(status)
    local body = BODIES[status]

    if body then
      return body
    end

    body = fmt(DEFAULT_FMT, status)
    BODIES[status] = body

    return body
  end
end


return function(ctx)
  local accept_header = kong.request.get_header(ACCEPT)
  if accept_header == nil then
    accept_header = kong.request.get_header(CONTENT_TYPE)
    if accept_header == nil then
      accept_header = kong.configuration.error_default_type
    end
  end

  local status = kong.response.get_status()
  local message = get_body(status)

  -- Nginx 494 status code is used internally when the client sends
  -- too large or invalid HTTP headers. Kong is obliged to convert
  -- it back to `400 Bad Request`.
  if status == 494 then
    status = 400
  end

  local headers
  if find(accept_header, TYPE_GRPC, nil, true) == 1 then
    message = { message = message }

  else
    local mime_type = tools_http.get_response_type(accept_header)
    local rid = request_id.get() or ""
    message = fmt(tools_http.get_error_template(mime_type), message, rid)
    headers = { [CONTENT_TYPE] = mime_type }

  end

  -- Reset relevant context values
  ctx.buffered_proxying = nil
  ctx.response_body = nil

  if ctx then
    ctx.delay_response = nil
    ctx.delayed_response = nil
    ctx.delayed_response_callback = nil
  end

  return kong.response.exit(status, message, headers)
end
