local kong = kong
local find = string.find
local fmt  = string.format
local utils = require "kong.tools.utils"


local CONTENT_TYPE    = "Content-Type"
local ACCEPT          = "Accept"
local TYPE_GRPC       = "application/grpc"


local BODIES = {
  s400 = "Bad request",
  s404 = "Not found",
  s408 = "Request timeout",
  s411 = "Length required",
  s412 = "Precondition failed",
  s413 = "Payload too large",
  s414 = "URI too long",
  s417 = "Expectation failed",
  s494 = "Request header or cookie too large",
  s500 = "An unexpected error occurred",
  s502 = "An invalid response was received from the upstream server",
  s503 = "The upstream server is currently unavailable",
  s504 = "The upstream server is timing out",
  default = "The upstream server responded with %d"
}


return function(ctx)
  local accept_header = kong.request.get_header(ACCEPT)
  if accept_header == nil then
    accept_header = kong.request.get_header(CONTENT_TYPE)
    if accept_header == nil then
      accept_header = kong.configuration.error_default_type
    end
  end

  local status = kong.response.get_status()
  local message = BODIES["s" .. status] or fmt(BODIES.default, status)

  local headers
  if find(accept_header, TYPE_GRPC, nil, true) == 1 then
    message = { message = message }

  else
    local mime_type = utils.get_mime_type(accept_header)
    message = fmt(utils.get_error_template(mime_type), message)
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
