local error = error


local ErrorGeneratorHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 1000000,
}


function ErrorGeneratorHandler:init_worker()
end


function ErrorGeneratorHandler:certificate(conf)
  if conf.certificate then
    error("[error-generator] certificate")
  end
end


function ErrorGeneratorHandler:rewrite(conf)
  if conf.rewrite then
    error("[error-generator] rewrite")
  end
end


function ErrorGeneratorHandler:preread(conf)
  if conf.preread then
    error("[error-generator] preread")
  end
end


function ErrorGeneratorHandler:access(conf)
  if conf.access then
    error("[error-generator] access")
  end
end


function ErrorGeneratorHandler:header_filter(conf)
  if conf.header_filter then
    error("[error-generator] header_filter")
  end
end


function ErrorGeneratorHandler:body_filter(conf)
  if conf.header_filter then
    error("[error-generator] body_filter")
  end
end


function ErrorGeneratorHandler:log(conf)
  if conf.log then
    error("[error-generator] body_filter")
  end
end



return ErrorGeneratorHandler
