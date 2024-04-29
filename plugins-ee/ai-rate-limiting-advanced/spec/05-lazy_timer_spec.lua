-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local fmt = string.format
local pl_utils = require "pl.utils"
local plugin_name = "ai-rate-limiting-advanced"

local function post_config(admin_client, yaml_file)
   local res = assert(admin_client:send {
     method = "POST",
     path = "/config",
     body = {
       config = pl_utils.readfile(yaml_file),
     },
     headers = {
       ["Content-Type"] = "application/json",
     }
   })
   return cjson.decode(assert.res_status(201, res))
end

local function patch_plugin(admin_client, plugin_id, config)
  local res = assert(admin_client:send {
    method = "PATCH",
    path = "/plugins/" .. plugin_id,
    body = {
      config = config,
    },
    headers = {
      ["Content-Type"] = "application/json",
    },
  })

  return cjson.decode(assert.res_status(200, res))
end

for _, strategy in helpers.all_strategies() do
  describe(fmt("%s - lazy timer [#%s]", plugin_name, strategy), function()
    local bp, db, admin_client, proxy_client, plugin_id
    local config1, config2, config3, config4
    local yaml_file_0, yaml_file_1, yaml_file_2, yaml_file_3, yaml_file_4, yaml_file_5
    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "routes",
        "services",
        "plugins",
      }, { plugin_name })

      local route = bp.routes:insert({ paths = { "/test" } })

      -- initial config
      config1 = {
        name = plugin_name,
        route = { id = route.id },
        config = {
          strategy = "redis",
          llm_providers = {{
            name = "openai",
            window_size = 5,
            limit = 3,
          }},
          sync_rate = 0.5,
          redis = {
            host = "invalid.test",
            port = helpers.redis_port,
            database = 1,
          },
        },
      }

      -- update limit
      config2 = {
        llm_providers = {{ 
          name = "openai",
          window_size = 2,
          limit = 3,
        }},
      }

      -- update sync_rate from 0.5 to -1
      config3 = {
        sync_rate = -1,
      }

      -- update sync_rate from -1 to 0.5
      config4 = {
        sync_rate = 0.5,
      }

      if strategy == "off" then
        yaml_file_0 = helpers.make_yaml_file()

        local plugin = bp.plugins:insert(config1)
        local plugin_id = plugin.id

        yaml_file_1 = helpers.make_yaml_file()

        bp.plugins:update({id = plugin_id}, {
          config = config2,
        })

        yaml_file_2 = helpers.make_yaml_file()

        bp.plugins:update({id = plugin_id}, {
          config = config3,
        })

        yaml_file_3 = helpers.make_yaml_file()

        bp.plugins:update({id = plugin_id}, {
          config = config4,
        })

        yaml_file_4 = helpers.make_yaml_file()

        db.plugins:delete({id = plugin_id})

        yaml_file_5 = helpers.make_yaml_file()
      end

      assert(helpers.start_kong({
        database   = strategy,
        plugins    = plugin_name,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and yaml_file_0 or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      helpers.clean_logfile()
      if admin_client then
        admin_client:close()
      end
    end)

    it("doesn't create the timer when a plugin is created", function()
      if strategy == "off" then
        post_config(admin_client, yaml_file_1)

      else
        local res = assert(admin_client:send {
          method = "POST",
          path = "/plugins/",
          body = config1,
          headers = {
            ["Content-Type"] = "application/json",
          },
        })
        local body = cjson.decode(assert.res_status(201, res))
        plugin_id = body.id
      end

      assert.logfile().has.no.line("creating timer for namespace openai", true, 5)
      assert.logfile().has.no.line("error in fetching counters for namespace openai", true, 5)
    end)

    it("create the timer when the plugin is first executed", function()
      proxy_client = helpers.proxy_client()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/test",
      })
      assert.res_status(200, res)
      proxy_client:close()
      assert.logfile().has.line("creating timer for namespace openai", true, 10)
      assert.logfile().has.line("error in fetching counters for namespace openai", true, 10)
    end)

    it("won't re-create a timer when the limit is updated", function()
      if strategy == "off" then
        post_config(admin_client, yaml_file_2)

      else
        patch_plugin(admin_client, plugin_id, config2)
      end
      assert.logfile().has.no.line("creating timer for namespace openai", true, 5)
    end)

    it("destroy the timer when sync_rate is changed from 0.5 to -1", function()
      if strategy == "off" then
        post_config(admin_client, yaml_file_3)

      else
        patch_plugin(admin_client, plugin_id, config3)
      end

      assert.logfile().has.line("rate-limiting strategy is not enabled: skipping sync", true, 10)

      helpers.pwait_until(function()
        helpers.clean_logfile()
        assert.logfile().has.no.line("error in fetching counters for namespace openai", true, 5)
      end, 20)
    end)

    it("don't create the timer immediately when sync_rate is changed from -1 to 0.5", function()
      if strategy == "off" then
        post_config(admin_client, yaml_file_4)

      else
        patch_plugin(admin_client, plugin_id, config4)
      end

      assert.logfile().has.no.line("creating timer for namespace openai", true, 5)
      assert.logfile().has.no.line("error in fetching counters for namespace openai", true, 5)
    end)

    it("create the timer again when the plugin is first executed", function()
      proxy_client = helpers.proxy_client()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/test",
      })
      assert.res_status(200, res)
      proxy_client:close()
      assert.logfile().has.line("creating timer for namespace openai", true, 10)
      assert.logfile().has.line("error in fetching counters for namespace openai", true, 10)
    end)


    it("destroy the timer when the plugin is deleted", function()
      if strategy == "off" then
        post_config(admin_client, yaml_file_5)

      else
        local res = assert(admin_client:send {
          method = "DELETE",
          path = "/plugins/" .. plugin_id,
        })
        assert.res_status(204, res)
      end
      assert.logfile().has.line("clearing old namespace openai", true, 10)
      assert.logfile().has.line("stale timer of namespace openai", true, 10)
    end)
  end)
end