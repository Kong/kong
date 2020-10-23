local log       = require "kong.plugins.openid-connect.log"
local responses = require "kong.plugins.openid-connect.responses"


local kong      = kong
local select    = select
local concat    = table.concat


return function(client, ...)
  local count = select("#", ...)

  if count > 0 then
    log.err(...)
  end

  if client.unexpected_redirect_uri then
    return responses.redirect(client.unexpected_redirect_uri)
  end

  local message = "An unexpected error occurred"

  if client.display_errors and count > 0 then
    local err
    if count == 1 then
      err = select(1, ...)
    else
      err = concat({ ... }, " ")
    end

    if err ~= "" then
      message = message .. " (" .. err .. ")"
    end
  end

  return kong.response.exit(500, { message = message })
end
