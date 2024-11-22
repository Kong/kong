-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local conf_loader = require "kong.conf_loader"
local dao_plugins = require "kong.db.dao.plugins"
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

local fmt = string.format

-- List of all bundled plugins + plugins from the /plugins-ee folder.
-- This is needed because EE plugins from `/plugins-ee`, defined in
-- distribution_constants, are only included in the `bundled` list
-- when the distribution_constants file is replaced/overwritten during the
-- build / package process (this does not happen in the local dev env).
local all_plugins = {
  "bundled",
  "graphql-rate-limiting-advanced",
  "jwt-signer",
  "kafka-log",
  "kafka-upstream",
  "ldap-auth-advanced",
  "mtls-auth",
  "oas-validation",
  "opa",
  "openid-connect",
  "proxy-cache-advanced",
  "ai-semantic-cache",
  "service-protection",
  "rate-limiting-advanced",
  "ai-rate-limiting-advanced",
  "request-validator",
  "vault-auth",
  "ai-azure-content-safety",
}

describe("Plugins", function()
  local plugins

  lazy_setup(function()
    local conf = assert(conf_loader(nil, {
      plugins = all_plugins,
      portal_and_vitals_key = get_portal_and_vitals_key()
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
      'json-threat-protection',
      'xml-threat-protection',
      'websocket-validator',
      'websocket-size-limit',
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
      "service-protection",
      'rate-limiting-advanced',
      'rate-limiting',
      'ai-rate-limiting-advanced',
      'graphql-rate-limiting-advanced',
      'response-ratelimiting',
      'route-by-header',
      'oas-validation',
      'jq',
      'request-transformer-advanced',
      'request-transformer',
      'response-transformer-advanced',
      'response-transformer',
      'route-transformer-advanced',
      'ai-request-transformer',
      'ai-semantic-prompt-guard',
      'ai-azure-content-safety',
      'ai-prompt-template',
      'ai-prompt-decorator',
      'ai-prompt-guard',
      'ai-proxy-advanced',
      'ai-proxy',
      'ai-response-transformer',
      "ai-semantic-cache",
      'standard-webhooks',
      'confluent',
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
