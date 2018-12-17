local lapis = require "lapis"
local prometheus = require "kong.plugins.prometheus.exporter"


local app = lapis.Application()


app.default_route = function(self)
  local path = self.req.parsed_url.path:match("^(.*)/$")

  if path and self.app.router:resolve(path, self) then
    return

  elseif self.app.router:resolve(self.req.parsed_url.path .. "/", self) then
    return
  end

  return self.app.handle_404(self)
end


app.handle_404 = function(self) -- luacheck: ignore 212
  local body = '{"message":"Not found"}'
  ngx.status = 404
  ngx.header["Content-Type"] = "application/json; charset=utf-8"
  ngx.header["Content-Length"] = #body + 1
  ngx.say(body)
end


app:match("/", function()
  kong.response.exit(200, "Kong Prometheus exporter, visit /metrics")
end)


app:match("/metrics", function()
  prometheus:collect()
end)


return {
  prometheus_server = function()
    return lapis.serve(app)
  end,
}
