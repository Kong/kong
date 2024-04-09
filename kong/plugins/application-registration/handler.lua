-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local acl = require "kong.plugins.acl.handler"
local enums  = require "kong.enterprise_edition.dao.enums"
local meta = require "kong.meta"

local kong = kong


local PortalAppHandler = {}

PortalAppHandler.PRIORITY = 995
PortalAppHandler.VERSION = meta.core_version


function PortalAppHandler:access(conf)
  conf.allow = { conf.service_id }

  local consumer = kong.client.get_consumer()
  if not consumer or consumer.type ~= enums.CONSUMERS.TYPE.APPLICATION then
    if consumer and conf.enable_proxy_with_consumer_credential
        and consumer.type == enums.CONSUMERS.TYPE.PROXY then
      return
    end

    return kong.response.exit(401, "Unauthorized")
  end

  acl:access(conf)
end


return PortalAppHandler
