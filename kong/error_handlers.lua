local meta = require "kong.meta"
local singletons = require "kong.singletons"
local constants = require "kong.constants"

local find = string.find
local format = string.format

local TYPE_PLAIN = "text/plain"
local TYPE_JSON = "application/json"
local TYPE_XML = "application/xml"
local TYPE_HTML = "text/html"

local text_template = "%s"
local json_template = '{"message":"%s"}'
local xml_template = '<?xml version="1.0" encoding="UTF-8"?>\n<error><message>%s</message></error>'
local html_template = '<html><head><title>Kong Error</title></head><body><h1>Kong Error</h1><p>%s.</p></body></html>'

local BODIES = {
  s400 = "Bad request",
  s404 = "Not found",
  s408 = "Request timeout",
  s411 = "Length required",
  s412 = "Precondition failed",
  s413 = "Payload too large",
  s414 = "URI too long",
  s417 = "Expectation failed",
  s494 = "Request Header Or Cookie Too Large",
  s500 = "An unexpected error occurred",
  s502 = "An invalid response was received from the upstream server",
  s503 = "The upstream server is currently unavailable",
  s504 = "The upstream server is timing out",
  default = "The upstream server responded with %d"
}

local SERVER_HEADER = meta._SERVER_TOKENS

return function(ngx)
  local accept_header = ngx.req.get_headers()["accept"]
  local template, message, content_type

  if accept_header == nil then
    accept_header = singletons.configuration.error_default_type
  end

  if find(accept_header, TYPE_HTML, nil, true) then
    template = html_template
    content_type = TYPE_HTML
  elseif find(accept_header, TYPE_JSON, nil, true) then
    template = json_template
    content_type = TYPE_JSON
  elseif find(accept_header, TYPE_XML, nil, true) then
    template = xml_template
    content_type = TYPE_XML
  else
    template = text_template
    content_type = TYPE_PLAIN
  end

  local status = ngx.status
  message = BODIES["s" .. status] or format(BODIES.default, status)

  if singletons.configuration.enabled_headers[constants.HEADERS.SERVER] then
    ngx.header[constants.HEADERS.SERVER] = SERVER_HEADER
  end

  ngx.header["Content-Type"] = content_type
  ngx.say(format(template, message))
end
