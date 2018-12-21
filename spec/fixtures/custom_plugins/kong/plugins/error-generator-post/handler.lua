local BasePlugin = require "kong.plugins.base_plugin"


local error = error


local ErrorGeneratorPostHandler = BasePlugin:extend()


ErrorGeneratorPostHandler.PRIORITY = -math.huge


function ErrorGeneratorPostHandler:new()
  ErrorGeneratorPostHandler.super.new(self, "logger")
end


function ErrorGeneratorPostHandler:init_worker()
  ErrorGeneratorPostHandler.super.init_worker(self)
end


function ErrorGeneratorPostHandler:certificate(conf)
  ErrorGeneratorPostHandler.super.certificate(self)

  if conf.certificate then
    error("[error-generator-post] certificate")
  end
end


function ErrorGeneratorPostHandler:rewrite(conf)
  ErrorGeneratorPostHandler.super.rewrite(self)

  if conf.rewrite then
    error("[error-generator-post] rewrite")
  end
end


function ErrorGeneratorPostHandler:access(conf)
  ErrorGeneratorPostHandler.super.access(self)

  if conf.access then
    error("[error-generator-post] access")
  end
end


function ErrorGeneratorPostHandler:header_filter(conf)
  ErrorGeneratorPostHandler.super.header_filter(self)

  if conf.header_filter then
    error("[error-generator-post] header_filter")
  end
end


function ErrorGeneratorPostHandler:body_filter(conf)
  ErrorGeneratorPostHandler.super.body_filter(self)

  if conf.header_filter then
    error("[error-generator-post] body_filter")
  end
end


function ErrorGeneratorPostHandler:log(conf)
  ErrorGeneratorPostHandler.super.log(self)

  if conf.log then
    error("[error-generator] body_filter")
  end
end


return ErrorGeneratorPostHandler
