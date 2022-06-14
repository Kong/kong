-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
