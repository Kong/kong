-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local oauth2 = require "kong.plugins.oauth2.handler"
local acl = require "kong.plugins.acl.handler"
local enums  = require "kong.enterprise_edition.dao.enums"


local kong = kong


local PortalAppHandler = {}

PortalAppHandler.PRIORITY = 1007
PortalAppHandler.VERSION = "1.0.0"


function PortalAppHandler:access(conf)
  conf.whitelist = { conf.service_id }

  oauth2:access(conf)

  local consumer = kong.client.get_consumer()
  if not consumer or consumer.type ~= enums.CONSUMERS.TYPE.APPLICATION then
    return kong.response.exit(401, "Unauthorized")
  end

  acl:access(conf)
end


return PortalAppHandler
