local BasePlugin = require "kong.plugins.base_plugin"


local error = error


local ErrorGeneratorPreHandler = BasePlugin:extend()


ErrorGeneratorPreHandler.PRIORITY = math.huge


function ErrorGeneratorPreHandler:new()
  ErrorGeneratorPreHandler.super.new(self, "logger")
end


function ErrorGeneratorPreHandler:init_worker()
  ErrorGeneratorPreHandler.super.init_worker(self)
end


function ErrorGeneratorPreHandler:certificate(conf)
  ErrorGeneratorPreHandler.super.certificate(self)

  if conf.certificate then
    error("[error-generator-pre] certificate")
  end
end


function ErrorGeneratorPreHandler:rewrite(conf)
  ErrorGeneratorPreHandler.super.rewrite(self)

  if conf.rewrite then
    error("[error-generator-pre] rewrite")
  end
end


function ErrorGeneratorPreHandler:access(conf)
  ErrorGeneratorPreHandler.super.access(self)

  if conf.access then
    error("[error-generator-pre] access")
  end
end


function ErrorGeneratorPreHandler:header_filter(conf)
  ErrorGeneratorPreHandler.super.header_filter(self)

  if conf.header_filter then
    error("[error-generator-pre] header_filter")
  end
end


function ErrorGeneratorPreHandler:body_filter(conf)
  ErrorGeneratorPreHandler.super.body_filter(self)

  if conf.header_filter then
    error("[error-generator-pre] body_filter")
  end
end


function ErrorGeneratorPreHandler:log(conf)
  ErrorGeneratorPreHandler.super.log(self)

  if conf.log then
    error("[error-generator] body_filter")
  end
end


return ErrorGeneratorPreHandler
