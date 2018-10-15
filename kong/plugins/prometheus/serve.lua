local lapis = require "lapis"
local prometheus = require "kong.plugins.prometheus.exporter"
local responses = require "kong.tools.responses"


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
  return responses.send_HTTP_NOT_FOUND()
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
