local error = error


local ErrorGeneratorLastHandler = {}


ErrorGeneratorLastHandler.PRIORITY = -math.huge


function ErrorGeneratorLastHandler:init_worker()
end


function ErrorGeneratorLastHandler:certificate(conf)
  if conf.certificate then
    error("[error-generator-last] certificate")
  end
end


function ErrorGeneratorLastHandler:rewrite(conf)
  if conf.rewrite then
    error("[error-generator-last] rewrite")
  end
end


function ErrorGeneratorLastHandler:preread(conf)
  if conf.preread then
    error("[error-generator-last] preread")
  end
end



function ErrorGeneratorLastHandler:access(conf)
  if conf.access then
    error("[error-generator-last] access")
  end
end


function ErrorGeneratorLastHandler:header_filter(conf)
  if conf.header_filter then
    error("[error-generator-last] header_filter")
  end
end


function ErrorGeneratorLastHandler:body_filter(conf)
  if conf.header_filter then
    error("[error-generator-last] body_filter")
  end
end


function ErrorGeneratorLastHandler:log(conf)
  if conf.log then
    error("[error-generator] body_filter")
  end
end


return ErrorGeneratorLastHandler
