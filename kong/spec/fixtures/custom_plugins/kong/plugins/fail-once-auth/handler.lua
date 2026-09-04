-- a plugin fixture to force one authentication failure

local FailOnceAuth =  {
  VERSION = "0.1-t",
  PRIORITY = 1000,
}

local failed = {}

function FailOnceAuth:access(conf)
  if not failed[conf.service_id] then
    failed[conf.service_id] = true
    return kong.response.exit(401, { message = conf.message })
  end
end

return FailOnceAuth
