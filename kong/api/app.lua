local lapis = require "lapis"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"

local Apis = require "kong.api.routes.apis"
local Consumers = require "kong.api.routes.consumers"
local PluginsConfigurations = require "kong.api.routes.plugins_configurations"

app = lapis.Application()

local function get_hostname()
  local f = io.popen ("/bin/hostname")
  local hostname = f:read("*a") or ""
  f:close()
  hostname = string.gsub(hostname, "\n$", "")
  return hostname
end

app:get("/", function(self)
  local db_plugins, err = dao.plugins_configurations:find_distinct()
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  return responses.send_HTTP_OK({
    tagline = "Welcome to Kong",
    version = constants.VERSION,
    hostname = get_hostname(),
    plugins = {
      available_on_server = configuration.plugins_available,
      enabled_in_cluster = db_plugins
    },
    lua_version = jit and jit.version or _VERSION
  })
end)

app.default_route = function(self)
  local path = self.req.parsed_url.path:match("^(.*)/$")

  if path and self.app.router:resolve(path, self) then
    return
  end

  return self.app.handle_404(self)
end

app.handle_404 = function(self)
  return responses.send_HTTP_NOT_FOUND()
end

app.handle_error = function(self, err, trace)
  ngx.log(ngx.ERR, err.."\n"..trace)

  local iterator, iter_err = ngx.re.gmatch(err, ".+:\\d+:\\s*(.+)")
  if iter_err then
    ngx.log(ngx.ERR, iter_err)
  end

  local m, iter_err = iterator()
  if iter_err then
    ngx.log(ngx.ERR, iter_err)
  end

  if m and table.getn(m) > 0 then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(m[1])
  else
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
end

-- Load controllers
Apis()
Consumers()
PluginsConfigurations()

-- Loading plugins routes
if configuration and configuration.plugins_available then
  for _, v in ipairs(configuration.plugins_available) do
    local status, res = pcall(require, "kong.plugins."..v..".api")
    if status then
      ngx.log(ngx.DEBUG, "Loading API endpoints for plugin: "..v)
      res()
    end
  end
end

return app
