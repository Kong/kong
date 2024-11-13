local access = require "kong.plugins.session.access"
local header_filter = require "kong.plugins.session.header_filter"
local kong_meta = require "kong.meta"


local KongSessionHandler = {
  PRIORITY = 1900,
  VERSION = kong_meta.version,
}


function KongSessionHandler:header_filter(conf)
  header_filter.execute(conf)
end


function KongSessionHandler:access(conf)
  access.execute(conf)
end


return KongSessionHandler
