local LoggerHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 1000,
}


function LoggerHandler:init_worker(conf)
  kong.log("init_worker phase")
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
