local plugin = require "kong.plugins.standard-webhooks.internal"

local StandardWebhooks = {
    VERSION = require("kong.meta").version,
    PRIORITY = 760
}

function StandardWebhooks:access(conf)
    plugin.access(conf)
end

return StandardWebhooks
