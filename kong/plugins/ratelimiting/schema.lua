local constants = require "kong.constants"
local stringy = require "stringy"
local utils = require "kong.tools.utils"


local function check_limit_period(value, table_t)
   for _,v in ipairs(value) do
      local parts = stringy.split(v, ':')
      if not utils.array_contains(constants.RATELIMIT.PERIODS, parts[1]) then
         return false, "The ratelimiting period should match any of the following durations : "..table.concat(constants.RATELIMIT.PERIODS, ',')
      end
   end
   return true
end

return {
  limit = { required = true, type = "table", func = check_limit_period },
}
