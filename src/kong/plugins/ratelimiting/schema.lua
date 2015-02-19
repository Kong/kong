local constants = require "kong.constants"

return {
  limit = { required = true },
  period = { required = true, enum = constants.RATELIMIT.PERIODS }
}
