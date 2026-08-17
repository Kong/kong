local common = require "kong.plugins.request-transformer.migrations.common"


return {
  {
    name = "2017-11-28-120000_request-transformer-advanced-rename",
    up   = common.rt_rename,
    down = function() end,
  },
}
