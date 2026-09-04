local log = require "kong.plugins.statsd.log"
local kong_meta = require "kong.meta"


local StatsdHandler = {
  PRIORITY = 11,
  VERSION = kong_meta.version,
}


function StatsdHandler:log(conf)
  log.execute(conf)
end


return StatsdHandler
