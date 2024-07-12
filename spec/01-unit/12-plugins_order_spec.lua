-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers" -- initializes 'kong' global for plugins
local conf_loader = require "kong.conf_loader"
local dao_plugins = require "kong.db.dao.plugins"
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

local fmt = string.format

describe("Plugins", function()
  local plugins

  lazy_setup(function()
    local conf = assert(conf_loader(nil, {
      plugins = "bundled",
      portal_and_vitals_key = get_portal_and_vitals_key()
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf)

    plugins = {}

    for plugin in pairs(conf.loaded_plugins) do
      if not helpers.is_enterprise_plugin(plugin) then
        local handler = require("kong.plugins." .. plugin .. ".handler")
        table.insert(plugins, {
          name    = plugin,
          handler = handler
        })
      end
    end
  end)

  it("don't have identical `PRIORITY` fields", function()
    local priorities = {}

    for _, plugin in ipairs(plugins) do
      local priority = plugin.handler.PRIORITY
      assert.not_nil(priority)

      if priorities[priority] then
        -- ignore colliding priorities for "advanced" and "enc" plugins
        if plugin.name:gsub("%-advanced", "") ~= priorities[priority]:gsub("%-advanced", "")
           and plugin.name:gsub("%-enc", "") ~= priorities[priority]:gsub("%-enc", "") then
            assert.fail(fmt("plugins have the same priority: '%s' and '%s' (%d)",
                        priorities[priority], plugin.name, priority))
        end
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
      "correlation-id",
      "zipkin",
      "exit-transformer",
      "bot-detection",
      "cors",
      "jwe-decrypt",
      "session",
      "acme",
      "oauth2-introspection",
      "degraphql",
      "jwt",
      "oauth2",
      "key-auth-enc",
      "key-auth",
      "ldap-auth",
      "basic-auth",
      "hmac-auth",
      "json-threat-protection",
      "xml-threat-protection",
      "websocket-validator",
      "websocket-size-limit",
      "grpc-gateway",
      "tls-handshake-modifier",
      "tls-metadata-headers",
      "application-registration",
      "ip-restriction",
      "request-size-limiting",
      "acl",
      "rate-limiting-advanced",
      "rate-limiting",
      "response-ratelimiting",
      "route-by-header",
      "jq",
      "request-transformer-advanced",
      "request-transformer",
      "response-transformer-advanced",
      "response-transformer",
      "route-transformer-advanced",
      "ai-request-transformer",
      "ai-semantic-prompt-guard",
      "ai-azure-content-safety",
      "ai-prompt-template",
      "ai-prompt-decorator",
      "ai-prompt-guard",
      "ai-proxy-advanced",
      "ai-proxy",
      "ai-response-transformer",
      "ai-semantic-cache",
      "standard-webhooks",
      "confluent",
      "aws-lambda",
      "azure-functions",
      "upstream-timeout",
      "proxy-cache-advanced",
      "proxy-cache",
      "graphql-proxy-cache-advanced",
      "forward-proxy",
      "canary",
      "opentelemetry",
      "prometheus",
      "http-log",
      "statsd-advanced",
      "statsd",
      "datadog",
      "file-log",
      "udp-log",
      "tcp-log",
      "loggly",
      "syslog",
      "grpc-web",
      "request-termination",
      "mocking",
      "post-function",
    }

    table.sort(plugins, dao_plugins.sort_by_handler_priority)

    local sorted_plugins = {}

    for _, plugin in ipairs(plugins) do
      table.insert(sorted_plugins, plugin.name)
    end

    assert.same(order, sorted_plugins)
  end)
end)
