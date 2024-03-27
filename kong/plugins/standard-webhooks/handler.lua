local plugin = require "kong.plugins.standard-webhooks.internal"

local StandardWebhooks = {
    VERSION = "1.0.0",
    PRIORITY = 760
}

function StandardWebhooks:access(conf)
    plugin.access(conf)
end

return StandardWebhooks
