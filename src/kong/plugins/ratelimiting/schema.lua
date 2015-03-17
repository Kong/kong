local constants = require "kong.constants"

return {
  limit = { required = true, type = "number" },
  period = { required = true, enum = constants.RATELIMIT.PERIODS }
}
