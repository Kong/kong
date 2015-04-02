local constants = require "kong.constants"
local utils = require "kong.tools.utils"
local lapis = require "lapis"
local Apis = require "kong.web.routes.apis"
local PluginsConfigurations = require "kong.web.routes.plugins_configurations"
local Consumers = require "kong.web.routes.consumers"

app = lapis.Application()

local function get_hostname()
    local f = io.popen ("/bin/hostname")
    local hostname = f:read("*a") or ""
    f:close()
    hostname =string.gsub(hostname, "\n$", "")
    return hostname
end

app:get("/", function(self)
  local db_plugins, err = dao.plugins_configurations:find_distinct()
  if err then
    ngx.log(ngx.ERR, tostring(err))
    return utils.show_error(500, tostring(err))
  end

  return utils.success({
    tagline = "Welcome to Kong",
    version = constants.VERSION,
    hostname = get_hostname(),
    plugins = {
      available_on_server = configuration.plugins_available,
      enabled_in_cluster = db_plugins
    }
  })
end)

app.handle_404 = function(self)
  return utils.not_found()
end

app.handle_error = function(self, err, trace)
  ngx.log(ngx.ERR, err.."\n"..trace)

  local iterator, iter_err = ngx.re.gmatch(err, ".+:\\d+:\\s*(.+)")
  if iter_err then
    ngx.log(ngx.ERR, err)
  end

  local m, err = iterator()
  if err then
    ngx.log(ngx.ERR, err)
  end

  if m and table.getn(m) > 0 then
    utils.show_error(500, m[1])
  else
    ngx.log(ngx.ERR, "Can't parse error")
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
