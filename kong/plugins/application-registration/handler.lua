local acl = require "kong.plugins.acl.handler"
local enums  = require "kong.enterprise_edition.dao.enums"


local kong = kong


local PortalAppHandler = {}

PortalAppHandler.PRIORITY = 995
PortalAppHandler.VERSION = "2.0.0"


function PortalAppHandler:access(conf)
  conf.whitelist = { conf.service_id }

  local consumer = kong.client.get_consumer()
  if not consumer or consumer.type ~= enums.CONSUMERS.TYPE.APPLICATION then
    return kong.response.exit(401, "Unauthorized")
  end

  acl:access(conf)
end


return PortalAppHandler
