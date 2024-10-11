-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fmt = string.format
local plugin_name = "rate-limiting-advanced"

local REDIS_HOST = helpers.redis_host
local REDIS_PORT = helpers.redis_port or 6379
local REDIS_DATABASE = 1

for _, strategy in helpers.all_strategies() do
  describe(fmt("%s - event hook test [#%s]", plugin_name, strategy), function()
    local bp, proxy_client

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "routes",
        "services",
        "plugins",
      }, { plugin_name })

      local route = bp.routes:insert({ paths = { "/test" } })
      bp.plugins:insert({
        name = plugin_name,
        route = { id = route.id },
        config = {
          namespace = "foo",
          strategy = "local",
          window_size = { 10 },
          limit = { 1 },
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            username = nil,
            password = nil,
          },
        },
      })

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
        event_hooks_enabled = "false",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("should not print warn log when event_hooks_enabled is false", function()
      proxy_client = helpers.proxy_client()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/test",
      })
      proxy_client:close()
      assert.res_status(200, res)

      -- trigger event_hooks.emit
      proxy_client = helpers.proxy_client()
      res = assert(proxy_client:send {
        method = "GET",
        path = "/test",
      })
      proxy_client:close()
      assert.res_status(429, res)

      assert.logfile().has.no.line("failed to emit event:", true, 0)
    end)
  end)
end
