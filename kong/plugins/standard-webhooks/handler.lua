-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local plugin = require "kong.plugins.standard-webhooks.internal"

local StandardWebhooks = {
    VERSION = require("kong.meta").core_version,
    PRIORITY = 760
}

function StandardWebhooks:access(conf)
    plugin.access(conf)
end

return StandardWebhooks
