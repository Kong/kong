-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http = require "resty.http"

local EnableBuffering = {
  PRIORITY = 1000000,
  VERSION = "1.0",
}


function EnableBuffering:access(conf)
  local httpc = http.new()
  httpc:set_timeout(1)

  for suffix = 0, conf.calls - 1 do
    local uri = "http://really.really.really.really.really.really.not.exists." .. suffix
    pcall(function()
      httpc:request_uri(uri)
    end)
  end
end


return EnableBuffering
