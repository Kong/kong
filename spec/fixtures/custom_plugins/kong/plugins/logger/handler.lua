-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local LoggerHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 1000,
}


function LoggerHandler:init_worker()
  kong.log("init_worker phase")
end


function LoggerHandler:configure(configs)
  kong.log("configure phase")
end


function LoggerHandler:certificate(conf)
  kong.log("certificate phase")
end


function LoggerHandler:preread(conf)
  kong.log("preread phase")
end


function LoggerHandler:rewrite(conf)
  kong.log("rewrite phase")
end


function LoggerHandler:access(conf)
  kong.log("access phase")
end


function LoggerHandler:header_filter(conf)
  kong.log("header_filter phase")
end


function LoggerHandler:body_filter(conf)
  kong.log("body_filter phase")
end


function LoggerHandler:log(conf)
  kong.log("log phase")
end


return LoggerHandler
