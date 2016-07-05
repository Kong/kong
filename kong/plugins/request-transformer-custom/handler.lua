local BasePlugin = require "kong.plugins.base_plugin"
local RequestTransformerCustomHandler = BasePlugin:extend()

function RequestTransformerCustomHandler:new()
    RequestTransformerCustomHandler.super.new(self, "request-transformer")
end

function RequestTransformerCustomHandler:access(conf)
    RequestTransformerCustomHandler.super.access(self)
    ngx.log(ngx.DEBUG, "here comes the foreword:" .. conf.foreword);
end

RequestTransformerCustomHandler.PRIORITY = 800

return RequestTransformerCustomHandler
