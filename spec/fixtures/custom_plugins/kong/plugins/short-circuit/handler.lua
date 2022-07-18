-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"


local kong = kong
local tostring = tostring
local init_worker_called = false


local ShortCircuitHandler =  {
  VERSION = "0.1-t",
  PRIORITY = 1000000,
}


function ShortCircuitHandler:init_worker()
  init_worker_called = true
end


function ShortCircuitHandler:access(conf)
  return kong.response.exit(conf.status, {
    status  = conf.status,
    message = conf.message,
  }, {
    ["Kong-Init-Worker-Called"] = tostring(init_worker_called),
  })
end


function ShortCircuitHandler:preread(conf)
  local message = cjson.encode({
    status             = conf.status,
    message            = conf.message,
    init_worker_called = init_worker_called,
  })
  return kong.response.exit(conf.status, message)
end


return ShortCircuitHandler
