-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local fmt = string.format
local plugin_name = "http-log"

for _, strategy in helpers.all_strategies() do
  describe(fmt("%s - old plugin compatibility [#%s]", plugin_name, strategy), function()
    local bp, proxy_client, yaml_file
    local recover_new_plugin

    lazy_setup(function()
      -- use the old version plugin
      recover_new_plugin = helpers.use_old_plugin(plugin_name)

      bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route = bp.routes:insert({ paths = { "/test" } })

      bp.plugins:insert({
        name = plugin_name,
        route = { id = route.id },
        config = {
          http_endpoint = fmt("http://%s:%s/post_log/http", helpers.mock_upstream_host, helpers.mock_upstream_port),
          custom_fields_by_lua = {
            new_field = "return 123",
            route = "return nil", -- unset route field
          },
        },
      })

      if strategy == "off" then
        yaml_file = helpers.make_yaml_file()
      end

      assert(helpers.start_kong({
        database   = strategy,
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

      -- wait for the log handler to execute
      ngx.sleep(5)

      assert.logfile().has.no.line("[error]", true, 0)
      assert.logfile().has.no.line("[alert]", true, 0)
      assert.logfile().has.no.line("[crit]", true, 0)
      assert.logfile().has.no.line("[emerg]", true, 0)
    end)
  end)
end
