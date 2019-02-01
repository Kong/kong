local BasePlugin = require "kong.plugins.base_plugin"


local error = error


local ErrorGeneratorHandler = BasePlugin:extend()


ErrorGeneratorHandler.PRIORITY = math.huge


function ErrorGeneratorHandler:new()
  ErrorGeneratorHandler.super.new(self, "error-generator")
end


function ErrorGeneratorHandler:init_worker()
  ErrorGeneratorHandler.super.init_worker(self)
end


function ErrorGeneratorHandler:certificate(conf)
  ErrorGeneratorHandler.super.certificate(self)

  if conf.certificate then
    error("[error-generator] certificate")
  end
end


function ErrorGeneratorHandler:rewrite(conf)
  ErrorGeneratorHandler.super.rewrite(self)

  if conf.rewrite then
    error("[error-generator] rewrite")
  end
end


function ErrorGeneratorHandler:preread(conf)
  ErrorGeneratorHandler.super.preread(self)

  if conf.preread then
    error("[error-generator] preread")
  end
end


function ErrorGeneratorHandler:access(conf)
  ErrorGeneratorHandler.super.access(self)

  if conf.access then
    error("[error-generator] access")
  end
end


function ErrorGeneratorHandler:header_filter(conf)
  ErrorGeneratorHandler.super.header_filter(self)

  if conf.header_filter then
    error("[error-generator] header_filter")
  end
end


function ErrorGeneratorHandler:body_filter(conf)
  ErrorGeneratorHandler.super.body_filter(self)

  if conf.header_filter then
    error("[error-generator] body_filter")
  end
end


function ErrorGeneratorHandler:log(conf)
  ErrorGeneratorHandler.super.log(self)

  if conf.log then
    error("[error-generator] body_filter")
  end
end


return ErrorGeneratorHandler
