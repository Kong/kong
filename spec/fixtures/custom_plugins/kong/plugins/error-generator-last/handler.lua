local BasePlugin = require "kong.plugins.base_plugin"


local error = error


local ErrorGeneratorLastHandler = BasePlugin:extend()


ErrorGeneratorLastHandler.PRIORITY = -math.huge


function ErrorGeneratorLastHandler:new()
  ErrorGeneratorLastHandler.super.new(self, "error-generator-last")
end


function ErrorGeneratorLastHandler:init_worker()
  ErrorGeneratorLastHandler.super.init_worker(self)
end


function ErrorGeneratorLastHandler:certificate(conf)
  ErrorGeneratorLastHandler.super.certificate(self)

  if conf.certificate then
    error("[error-generator-last] certificate")
  end
end


function ErrorGeneratorLastHandler:rewrite(conf)
  ErrorGeneratorLastHandler.super.rewrite(self)

  if conf.rewrite then
    error("[error-generator-last] rewrite")
  end
end


function ErrorGeneratorLastHandler:preread(conf)
  ErrorGeneratorLastHandler.super.preread(self)

  if conf.preread then
    error("[error-generator-last] preread")
  end
end



function ErrorGeneratorLastHandler:access(conf)
  ErrorGeneratorLastHandler.super.access(self)

  if conf.access then
    error("[error-generator-last] access")
  end
end


function ErrorGeneratorLastHandler:header_filter(conf)
  ErrorGeneratorLastHandler.super.header_filter(self)

  if conf.header_filter then
    error("[error-generator-last] header_filter")
  end
end


function ErrorGeneratorLastHandler:body_filter(conf)
  ErrorGeneratorLastHandler.super.body_filter(self)

  if conf.header_filter then
    error("[error-generator-last] body_filter")
  end
end


function ErrorGeneratorLastHandler:log(conf)
  ErrorGeneratorLastHandler.super.log(self)

  if conf.log then
    error("[error-generator] body_filter")
  end
end


return ErrorGeneratorLastHandler
