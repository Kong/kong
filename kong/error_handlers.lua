local kong = kong
local find = string.find
local fmt  = string.format


local CONTENT_TYPE    = "Content-Type"
local ACCEPT          = "Accept"


local TYPE_JSON       = "application/json"
local TYPE_GRPC       = "application/grpc"
local TYPE_HTML       = "text/html"
local TYPE_XML        = "application/xml"


local JSON_TEMPLATE = [[
{
  "message": "%s"
}
]]


local HTML_TEMPLATE = [[
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Kong Error</title>
  </head>
  <body>
    <h1>Kong Error</h1>
    <p>%s.</p>
  </body>
</html>
]]


local XML_TEMPLATE = [[
<?xml version="1.0" encoding="UTF-8"?>
<error>
  <message>%s</message>
</error>
]]


local PLAIN_TEMPLATE = "%s\n"


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
  if find(accept_header, TYPE_JSON, nil, true) == 1 then
    message = fmt(JSON_TEMPLATE, message)
    headers = {
      [CONTENT_TYPE] = "application/json; charset=utf-8"
    }

  elseif find(accept_header, TYPE_GRPC, nil, true) == 1 then
    message = { message = message }

  elseif find(accept_header, TYPE_HTML, nil, true) == 1 then
    message = fmt(HTML_TEMPLATE, message)
    headers = {
      [CONTENT_TYPE] = "text/html; charset=utf-8"
    }

  elseif find(accept_header, TYPE_XML, nil, true) == 1 then
    message = fmt(XML_TEMPLATE, message)
    headers = {
      [CONTENT_TYPE] = "application/xml; charset=utf-8"
    }

  else
    message = fmt(PLAIN_TEMPLATE, message)
    headers = {
      [CONTENT_TYPE] = "text/plain; charset=utf-8"
    }
  end

  -- Reset relevant context values
  kong.ctx.core.buffered_proxying = nil
  kong.ctx.core.response_body = nil

  if ctx then
    ctx.delay_response = nil
    ctx.delayed_response = nil
    ctx.delayed_response_callback = nil
  end

  return kong.response.exit(status, message, headers)
end
