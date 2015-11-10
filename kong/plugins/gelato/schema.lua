local utils = require "kong.tools.utils"
local stringy = require "stringy"

local function generate_if_missing(v, t, column)
  if not v or stringy.strip(v) == "" then
    return true, nil, { [column] = utils.random_string()}
  end
  return true
end

return {
  no_consumer = true,
  fields = {
    secret = { type = "string", required = false, unique = true, func = generate_if_missing }
  }
}
