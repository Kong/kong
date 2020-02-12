require "spec.helpers" -- initializes 'kong' global for plugins
local conf_loader = require "kong.conf_loader"


local fmt = string.format


describe("Plugins", function()
  local plugins

  lazy_setup(function()
    local conf = assert(conf_loader(nil, {
      plugins = "bundled",
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf, nil)

    plugins = {}

    for plugin in pairs(conf.loaded_plugins) do
      local handler = require("kong.plugins." .. plugin .. ".handler")
      table.insert(plugins, {
        name    = plugin,
        handler = handler
      })
    end
  end)

  it("don't have identical `PRIORITY` fields", function()
    local priorities = {}

    for _, plugin in ipairs(plugins) do
      local priority = plugin.handler.PRIORITY
      assert.not_nil(priority)

      if priorities[priority] then
        assert.fail(fmt("plugins have the same priority: '%s' and '%s' (%d)",
                        priorities[priority], plugin.name, priority))
      end

      priorities[priority] = plugin.name
    end
  end)

  it("run in the following order", function()
    -- here is the order as of 0.10.1 with OpenResty 1.11.2.2
    --
    -- since 1.11.2.3 and the LuaJIT string hashing change, we hard-code
    -- that those plugins execute in this order, only to preserve
    -- backwards-compatibility

    local order = {
      "pre-function",
      "zipkin",
      "bot-detection",
      "cors",
      "session",
      "jwt",
      "oauth2",
      "key-auth",
      "ldap-auth",
      "basic-auth",
      "hmac-auth",
      "acme",
      "ip-restriction",
      "request-size-limiting",
      "acl",
      "rate-limiting",
      "response-ratelimiting",
      "request-transformer",
      "response-transformer",
      "aws-lambda",
      "azure-functions",
      "proxy-cache",
      "prometheus",
      "http-log",
      "statsd",
      "datadog",
      "file-log",
      "udp-log",
      "tcp-log",
      "loggly",
      "syslog",
      "request-termination",
      "correlation-id",
      "post-function",
    }

    table.sort(plugins, function(a, b)
      local priority_a = a.handler.PRIORITY or 0
      local priority_b = b.handler.PRIORITY or 0

      return priority_a > priority_b
    end)

    local sorted_plugins = {}

    for _, plugin in ipairs(plugins) do
      table.insert(sorted_plugins, plugin.name)
    end

    assert.same(order, sorted_plugins)
  end)
end)
