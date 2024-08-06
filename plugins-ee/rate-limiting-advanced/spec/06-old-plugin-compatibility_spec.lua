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
  describe(fmt("%s - old plugin compatibility [#%s]", plugin_name, strategy), function()
    local bp, proxy_client, yaml_file
    local policy = strategy == "off" and "redis" or "cluster"
    local recover_new_plugin
    local sync_rate = 0.1

    lazy_setup(function()
      -- use the old version plugin
      recover_new_plugin = helpers.use_old_plugin(plugin_name)

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
          strategy = policy,
          window_size = { 5 },
          limit = { 3 },
          sync_rate = sync_rate,
          redis = {
            host = REDIS_HOST,
            port = REDIS_PORT,
            database = REDIS_DATABASE,
            username = nil,
            password = nil,
          },
        },
      })

      if strategy == "off" then
        yaml_file = helpers.make_yaml_file()
      end

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and yaml_file or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      -- recover the new version plugin
      recover_new_plugin()
    end)

    before_each(function()
      helpers.clean_logfile()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("should not throw exception when using old version plugin together with the new core", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/test",
      })
      assert.not_same(500, res.status)

      -- make sure the sync handler is executed
      ngx.sleep(sync_rate * 2 + 1)

      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[alert]", true, 0)
      assert.logfile().has.no.line("[crit]", true, 0)
      assert.logfile().has.no.line("[emerg]", true, 0)
    end)
  end)
end
