-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local conf_loader = require "kong.conf_loader"
local dao_plugins = require "kong.db.dao.plugins"

local fmt = string.format

local ee_plugins = {
  "bundled",
  "canary",
  "degraphql",
  "exit-transformer",
  "forward-proxy",
  "graphql-proxy-cache-advanced",
  "graphql-rate-limiting-advanced",
  "jq",
  "jwt-signer",
  "kafka-log",
  "kafka-upstream",
  "key-auth-enc",
  "ldap-auth-advanced",
  "mocking",
  "mtls-auth",
  "oauth2-introspection",
  "opa",
  "openid-connect",
  "proxy-cache-advanced",
  "rate-limiting-advanced",
  "request-transformer-advanced",
  "request-validator",
  "response-transformer-advanced",
  "route-by-header",
  "route-transformer-advanced",
  "statsd-advanced",
  "tls-handshake-modifier",
  "tls-metadata-headers",
  "upstream-timeout",
  "vault-auth",
  "jwe-decrypt"
}

describe("Plugins", function()
  local plugins

  lazy_setup(function()
    local conf = assert(conf_loader(nil, {
      plugins = ee_plugins,
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf, nil)

    plugins = {}

    for plugin in pairs(conf.loaded_plugins) do
      local ok, handler = pcall(require, "kong.plugins." .. plugin .. ".handler")
      assert(ok, handler)
      table.insert(plugins, {
        name    = plugin,
        handler = handler
      })
    end
  end)

  it("don't have identical `PRIORITY` fields", function()
    local priorities = {}
    local errors = {}

    for _, plugin in ipairs(plugins) do
      local priority = plugin.handler.PRIORITY
      assert.not_nil(priority)
      local plugin_with_colliding_priority = priorities[priority]
      if plugin_with_colliding_priority ~= nil then
        -- %-advanced and %-enc are ee-counterpart plugins and can be ignored in this test
        if not ((plugin.name:gsub("%-advanced", "") == plugin_with_colliding_priority) or
            (plugin_with_colliding_priority:gsub("%-advanced", "") == plugin.name) or
            (plugin.name:gsub("%-enc", "") == plugin_with_colliding_priority) or
            (plugin_with_colliding_priority:gsub("%-enc", "") == plugin.name)) then
          table.insert(errors, fmt("plugins have the same priority: '%s' and '%s' (%d)", priorities[priority], plugin.name, priority))
        end
      end
      priorities[priority] = plugin.name
    end
    if errors then
      assert.is_same({}, errors)
    end
  end)


  it("test sort_by_handler_prio", function()
    local sort_list = {
      {
        handler = {
          PRIORITY = 10
        },
        name = "x-plugin"
      },
      {
        handler = {
          PRIORITY = 10
        },
        name = "x-plugin-advanced"
      },
    }
    table.sort(sort_list, dao_plugins.sort_by_handler_priority)
    assert.equal("x-plugin-advanced", sort_list[1].name)
    assert.equal("x-plugin", sort_list[2].name)
  end)


  it("run in the following order", function()
    -- here is the order as of 0.10.1 with OpenResty 1.11.2.2
    --
    -- since 1.11.2.3 and the LuaJIT string hashing change, we hard-code
    -- that those plugins execute in this order, only to preserve
    -- backwards-compatibility
    local order = {
      'pre-function',
      'correlation-id',
      'zipkin',
      'exit-transformer',
      'bot-detection',
      'cors',
      'jwe-decrypt',
      'session',
      -- acme needs to happen before auth plugins
      'acme',
      -- authn start
      -- EE
      'oauth2-introspection',
      'mtls-auth',
      'degraphql',
      'jwt',
      'oauth2',
      'vault-auth',
      'key-auth-enc',
      'key-auth',
      'ldap-auth-advanced',
      'ldap-auth',
      'basic-auth',
      'openid-connect',
      'hmac-auth',
      'jwt-signer',
      -- authn end
      'request-validator',
      'grpc-gateway',
      -- handshake before tls-metadata-headers
      'tls-handshake-modifier',
      -- metadata after hanshake modifiers
      'tls-metadata-headers',
      'application-registration',
      'ip-restriction',
      'request-size-limiting',
      -- authz
      'acl',
      'opa',
      -- authz
      'rate-limiting-advanced',
      'rate-limiting',
      'graphql-rate-limiting-advanced',
      'response-ratelimiting',
      'route-by-header',
      'jq',
      'request-transformer-advanced',
      'request-transformer',
      'response-transformer-advanced',
      'response-transformer',
      'route-transformer-advanced',
      'kafka-upstream',
      'aws-lambda',
      'azure-functions',
      'upstream-timeout',
      'proxy-cache-advanced',
      'proxy-cache',
      'graphql-proxy-cache-advanced',
      'forward-proxy',
      'canary',
      -- log start
      'opentelemetry',
      'prometheus',
      'http-log',
      'statsd-advanced',
      'statsd',
      'datadog',
      'file-log',
      'udp-log',
      'tcp-log',
      'loggly',
      'kafka-log',
      'syslog',
      -- log end
      'grpc-web',
      'request-termination',
      'mocking',
      'post-function',
    }

    table.sort(plugins, dao_plugins.sort_by_handler_priority)

    local sorted_plugins = {}

    for _, plugin in ipairs(plugins) do
      table.insert(sorted_plugins, plugin.name)
    end

    assert.same(order, sorted_plugins)
  end)
end)
