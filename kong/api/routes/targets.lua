local responses = require "kong.tools.responses"

local not_found = function()
  return responses.send_HTTP_NOT_FOUND()
end

return {
  -- deactivate endpoints (use /upstream/{upstream}/targets instead)
  ["/targets"] = {
    before = not_found,
  },
  ["/targets/:targets"] = {
    before = not_found,
  },
  ["/targets/:targets/upstream"] = {
    before = not_found,
  }
}
