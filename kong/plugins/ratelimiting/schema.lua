local constants = require "kong.constants"

return {
  limit = { required = true, type = "number" },
  period = { required = true, type = "string", enum = constants.RATELIMIT.PERIODS }
}
