-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong

local PreserveNullsHandler = {
  PRIORITY = 1000,
  VERSION = "0.1.0",
}

function PreserveNullsHandler:access(plugin_conf)
  kong.service.request.set_header(plugin_conf.request_header, "this is on a request")
end

function PreserveNullsHandler:header_filter(plugin_conf)
  kong.response.set_header(plugin_conf.response_header, "this is on the response")
end


return PreserveNullsHandler
