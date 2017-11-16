local common = require "kong.plugins.rate-limiting-advanced.migrations.common"

return {
  {
    name = "2017-11-16-120000_rename",
    up = common.ee_rename,
    down = function() end,
  },
}
