local singletons = require "kong.singletons"
local constants = require "kong.constants"
local meta = require "kong.meta"


local kong = kong
local server_header = meta._SERVER_TOKENS


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
RequestTerminationHandler.VERSION = "2.0.0"


function RequestTerminationHandler:access(conf)
  local status  = conf.status_code
  local content = conf.body

  if content then
    local headers = {
      ["Content-Type"] = conf.content_type
    }

    if singletons.configuration.enabled_headers[constants.HEADERS.SERVER] then
      headers[constants.HEADERS.SERVER] = server_header
    end

    return kong.response.exit(status, content, headers)
  end

  local message = conf.message or DEFAULT_RESPONSE[status]
  return kong.response.exit(status, message and { message = message } or nil)
end


return RequestTerminationHandler
