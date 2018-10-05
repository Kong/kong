local BasePlugin = require "kong.plugins.base_plugin"
local cjson = require "cjson.safe"


local PDKServiceRequestHandler = BasePlugin:extend()


PDKServiceRequestHandler.PRIORITY = 1000


function PDKServiceRequestHandler:new()
  PDKServiceRequestHandler.super.new(self, "pdk-service-request")
end


function PDKServiceRequestHandler:access(conf)
  PDKServiceRequestHandler.super.access(self)

  local err = {}
 
  local method = kong.service.request.get_method()
  local scheme = kong.service.request.get_scheme()
  local host = kong.service.request.get_host()
  local port = kong.service.request.get_port()
  local path = kong.service.request.get_path()

  local raw_query = kong.service.request.get_raw_query()
  local query = kong.service.request.get_query()
  local query_max_2 = kong.service.request.get_query(2)
  local query_foo = kong.service.request.get_query_arg("Foo")
  local query_lower_foo = kong.service.request.get_query_arg("foo")
  local query_bar = kong.service.request.get_query_arg("Bar")

  if pcall(kong.service.request.get_query, "invalid") then
    table.insert(err, "get_query() should raise error when trying to fetch with max_args invalid value")
  end
  if pcall(kong.service.request.get_query, 0) then
    table.insert(err, "get_query() should raise error when trying to fetch with max_args < 1")
  end
  if pcall(kong.service.request.get_query, 1001) then
    table.insert(err, "get_query() should raise error when trying to fetch with max_args > 1000")
  end

  local header_foo = kong.service.request.get_header("X-Foo-Header")
  local header_lower_foo = kong.service.request.get_header("x-foo-header")
  local header_underscode_foo = kong.service.request.get_header("x_foo_header")
  local header_bar = kong.service.request.get_header("X-Bar-Header")
  local headers = kong.service.request.get_headers()
  local headers_max_2 = kong.service.request.get_headers(2)

  if pcall(kong.service.request.get_header) then
    table.insert(err, "get_header() should raise error when trying to fetch with invalid argument")
  end
  if pcall(kong.service.request.get_headers, 0) then
    table.insert(err, "get_headers() should raise error when trying to fetch with max_headers < 1")
  end
  if pcall(kong.service.request.get_headers, 1001) then
    table.insert(err, "get_headers() should raise error when trying to fetch with max_headers > 1000")
  end

  local res = {
    method = method, scheme = scheme, host = host, port = port, path = path,
    raw_query = raw_query, query = query, query_max_2 = query_max_2,
    query_foo = query_foo, query_lower_foo = query_lower_foo, query_bar = query_bar,
    header_foo = header_foo, header_lower_foo = header_lower_foo,
    header_underscode_foo = header_underscode_foo, header_bar = header_bar,
    headers = headers, headers_max_2 = headers_max_2, err = err }
  local encoded = cjson.encode(res)

  ngx.say(encoded)
  ngx.exit(200)
end

return PDKServiceRequestHandler
