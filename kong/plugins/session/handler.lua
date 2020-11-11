local access = require "kong.plugins.session.access"
local header_filter = require "kong.plugins.session.header_filter"


local KongSessionHandler = {
  PRIORITY = 1900,
  VERSION  = "2.4.3",
}


function KongSessionHandler.header_filter(_, conf)
  header_filter.execute(conf)
end


function KongSessionHandler.access(_, conf)
  access.execute(conf)
end


return KongSessionHandler
