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
