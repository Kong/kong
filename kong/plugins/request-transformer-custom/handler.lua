local BasePlugin = require "kong.plugins.base_plugin"
local req_set_uri_args = ngx.req.set_uri_args
local req_get_uri_args = ngx.req.get_uri_args

local RequestTransformerCustomHandler = BasePlugin:extend()

function RequestTransformerCustomHandler:new()
    RequestTransformerCustomHandler.super.new(self, "request-transformer-custom")
end

function RequestTransformerCustomHandler:access(conf)
    RequestTransformerCustomHandler.super.access(self)
    -- Replace querystring(s)
    local querystring = req_get_uri_args()
    for name, value in pairs(conf.transform) do
        if querystring[name] then
            querystring[value] = querystring[name]
            querystring[name] = nil
        end
    end
    req_set_uri_args(querystring)
end

RequestTransformerCustomHandler.PRIORITY = 800
return RequestTransformerCustomHandler
