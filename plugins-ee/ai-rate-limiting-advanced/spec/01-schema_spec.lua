-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ai_rate_limiting_schema = require "kong.plugins.ai-rate-limiting-advanced.schema"
local v = require("spec.helpers").validate_plugin_config_schema
local helpers = require "spec.helpers"
local cjson = require "cjson"
local fmt = string.format
local pl_utils = require "pl.utils"
local plugin_name = "ai-rate-limiting-advanced"

local kong = kong
local concat = table.concat

local conf_err = concat{ "[ai-rate-limiting-advanced] ",
                         "strategy 'cluster' is not supported with Hybrid deployments or DB-less mode. ",
                         "If you did not specify the strategy, please use 'redis' strategy, 'local' strategy ",
                         "or set 'sync_rate' to -1.", }


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

local function post_plugin(admin_client, config)
  local res = assert(admin_client:send {
    method = "POST",
    path = "/plugins/",
    body = config,
    headers = {
      ["Content-Type"] = "application/json",
    },
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


describe("ai-rate-limiting-advanced schema", function()
  it("accepts a minimal config", function()
    local config, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
    }, ai_rate_limiting_schema)

    assert.is_truthy(config)
    assert.equal("local", config.config.strategy)
    assert.is_nil(err)
  end)

  it("accepts a minimal cluster config", function()
    local ok, err = v({
      strategy = "cluster",
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      sync_rate = 10,
    }, ai_rate_limiting_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("accepts a config with a custom identifier", function()
    local ok, err = v({
      strategy = "cluster",
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      identifier = "consumer",
      sync_rate = 10,
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts a config with a custom identifier [consumer-group]", function()
    local ok, err = v({
      strategy = "cluster",
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      identifier = "consumer-group",
      sync_rate = 10,
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts a config with a header identifier", function()
    local ok, err = v({
      strategy = "cluster",
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      identifier = "header",
      sync_rate = 10,
      header_name = "X-Email-Address",
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it ("errors with a `header` identifier without a `header_name`", function()
    local ok, err = v({
      strategy = "cluster",
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      identifier = "header",
      sync_rate = 10,
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "No header name provided" }, err["@entity"])
  end)

  it("accepts a config with a path identifier", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      identifier = "path",
      path = "/request",
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("errors with path identifier if path is missing", function()
    local ok, err = v({
      strategy = "cluster",
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      identifier = "path",
      sync_rate = 10,
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "No path provided" }, err["@entity"])
  end)

  it("casts window_size and window_limit values to numbers", function()
    local schema = {
      llm_providers = {{
        name = "openai",
        window_size = 10,
        limit = 50,
      },{
        name = "azure",
        window_size = 20,
        limit = 75,
      }},
      identifier = "consumer",
    }

    local ok, err = v(schema, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    for _, provider_config in ipairs(schema.llm_providers) do
      assert.is_number(provider_config.window_size)
    end

    for _, provider_config in ipairs(schema.llm_providers) do
      assert.is_number(provider_config.limit)
    end
  end)

  it("errors with an invalid size/limit type", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = "foo",
      }},
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same("expected a number", err.config.llm_providers[1].limit)
  end)

  it("errors with similar provider", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 1,
      },{
        name = "openai",
        window_size = 50,
        limit = 2,
      }},
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "Provider 'openai' is not unique" }, err["@entity"])
  end)

  it("errors with missing requing field", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 10,
        limit = 50,
      },{
        name = "azure",
      }}
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same("required field missing", err.config.llm_providers[2].window_size)
    assert.same("required field missing", err.config.llm_providers[2].limit)
  end)

  it("should return an error if requestPrompt provider is used without request prompt count function", function()
    local ok, err = v({
      llm_providers = {{
        name = "requestPrompt",
        window_size = 60,
        limit = 10,
      }},
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "You must provide request prompt count function when using requestPrompt provider" }, err["@entity"])
  end)

  it("ok if requestPrompt provider is used with request prompt count function", function()
    local ok, err = v({
      llm_providers = {{
        name = "requestPrompt",
        window_size = 60,
        limit = 10,
      }},
      request_prompt_count_function = "return 100"
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts a redis config", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = "127.0.0.1",
        port = 6379,
      },
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)

    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      sync_rate = 10,
      strategy = "redis",
      redis = {
        cluster_addresses = { "127.0.0.1:26379" }
      },
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)


    -- host & port getting defeault values
    local entity, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      sync_rate = 10,
      strategy = "redis",
    }, ai_rate_limiting_schema)
    assert.is_nil(err)
    assert.is_truthy(entity)
    assert.same(entity.config.redis.host, "127.0.0.1")
    assert.same(entity.config.redis.port, 6379)

    local entity, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = "example.com",
      }
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
    assert.same(entity.config.redis.host, "example.com")
    assert.same(entity.config.redis.port, 6379)

    local entity, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      sync_rate = 10,
      strategy = "redis",
      redis = {
        port = 7100,
      }
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(entity)
    assert.same(entity.config.redis.host, "127.0.0.1")
    assert.same(entity.config.redis.port, 7100)
  end)

  it("errors with a missing/incomplete redis config", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      sync_rate = 10,
      strategy = "redis",
      redis = {
        host = ngx.null,
        port = ngx.null
      }
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "No redis config provided" }, err["@entity"])

    local ok = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      sync_rate = 10,
      strategy = "redis",
      redis = {
        sentinel_master = "example.com",
      }
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
  end)

  it("accepts a hide_client_headers config", function ()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      hide_client_headers = true,
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts a retry_after_jitter_max config", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      retry_after_jitter_max = 1,
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("errors with NaN retry_after_jitter_max config", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      retry_after_jitter_max = "not a number",
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same("expected a number", err.config.retry_after_jitter_max)
  end)

  it("errors with a negative retry_after_jitter_max config", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      retry_after_jitter_max = -1,
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "Non-negative retry_after_jitter_max value is expected" }, err["@entity"])
  end)

  it("rejects sync_rate values between 0 and 0.02", function()
    local ok, err = v({
      strategy = "cluster",
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      sync_rate = 0.01,
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "Config option 'sync_rate' must not be a decimal between 0 and 0.02" }, err["@entity"])
  end)

  it("accepts a local strategy with no sync_rate", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      strategy = "local",
      -- sync_rate is no longer required
    }, ai_rate_limiting_schema)

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects a local strategy with sync_rate different than -1", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      strategy = "local",
      sync_rate = 1,
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "sync_rate cannot be configured when using a local strategy" }, err["@entity"])
  end)

  it("accepts a local strategy with sync_rate set to -1", function()
    local ok, _ = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      strategy = "local",
      sync_rate = -1,
    }, ai_rate_limiting_schema)

    assert.is_truthy(ok)
    assert.same(-1, ok.config.sync_rate)
  end)

  it("accept a cluster strategy", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      strategy = "cluster",
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ "sync_rate is required if not using a local strategy" }, err["@entity"])
  end)
end)

describe("DB-less mode schema validation", function()
  local db_bak = kong.configuration.database

  lazy_setup(function()
    rawset(kong.configuration, "database", "off")
  end)

  lazy_teardown(function()
    rawset(kong.configuration, "database", db_bak)
  end)

  it("rejects a cluster strategy with DB-less mode", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      strategy = "cluster",
      sync_rate = 1,
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ conf_err }, err["@entity"])
  end)

  it("accepts the cluster strategy with DB-less mode when sync_rate is -1", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      strategy = "cluster",
      sync_rate = -1,
    }, ai_rate_limiting_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
end)

describe("Hybrid mode schema validation", function()
  local role_bak = kong.configuration.role

  lazy_setup(function()
    rawset(kong.configuration, "role", "hybrid")
  end)

  lazy_teardown(function()
    rawset(kong.configuration, "role", role_bak)
  end)

  it("rejects a cluster strategy with DB-less mode", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      strategy = "cluster",
      sync_rate = 1,
    }, ai_rate_limiting_schema)

    assert.is_falsy(ok)
    assert.same({ conf_err }, err["@entity"])
  end)

  it("accepts the cluster strategy with Hybrid mode when sync_rate is -1", function()
    local ok, err = v({
      llm_providers = {{
        name = "openai",
        window_size = 60,
        limit = 10,
      }},
      strategy = "cluster",
      sync_rate = -1,
    }, ai_rate_limiting_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
end)

for _, strategy in helpers.all_strategies() do
  describe(fmt("%s - namespace configuration consistency [#%s]", plugin_name, strategy), function()
    local bp, admin_client, plugin_id
    local config1, config2, config3
    local yaml_file_0, yaml_file_1, yaml_file_2
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "routes",
        "services",
        "plugins",
      }, { plugin_name })

      local route1 = bp.routes:insert({ paths = { "/test1" } })
      local route2 = bp.routes:insert({ paths = { "/test2" } })

      -- two plugins with the same namespace but different configs
      config1 = {
        name = plugin_name,
        route = { id = route1.id },
        config = {
          strategy = "redis",
          llm_providers = {{
            name = "openai",
            window_size = 5,
            limit = 3,
          }},
          sync_rate = 0.5,
          redis = {
            host = "invalid.test",  -- different
            port = helpers.redis_port,
            database = 1,
          },
        },
      }

      config2 = {
        name = plugin_name,
        route = { id = route2.id },
        config = {
          strategy = "redis",
          llm_providers = {{
            name = "openai",
            window_size = 5,
            limit = 3,
          }},
          sync_rate = 0.5,
          redis = {
            host = "invalid2.test", -- different
            port = helpers.redis_port,
            database = 1,
          },
        },
      }

      config3 = {
        redis = {
          host = "invalid.test", -- same as in config1
          port = helpers.redis_port,
          database = 1,
        },
      }

      if strategy == "off" then
        yaml_file_0 = helpers.make_yaml_file()

        bp.plugins:insert(config1)
        local plugin = bp.plugins:insert(config2)

        yaml_file_1 = helpers.make_yaml_file()

        bp.plugins:update({id = plugin.id}, {
          config = config3,
        })

        yaml_file_2 = helpers.make_yaml_file()
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

    it("should not have error log as plugins use plugin id in namespace so ok to have different counter syncing configurations", function()
      if strategy == "off" then
        post_config(admin_client, yaml_file_1)

      else
        post_plugin(admin_client, config1)
        local plugin = post_plugin(admin_client, config2)
        plugin_id = plugin.id
      end

      assert.logfile().has.no.line("multiple ai-rate-limiting-advanced plugins with the namespace 'openai' have different counter syncing configurations", true, 10)
    end)

    it("should not have error log after changing to the same configuration", function()
      if strategy == "off" then
        post_config(admin_client, yaml_file_2)

      else
        patch_plugin(admin_client, plugin_id, config3)
      end

      assert.logfile().has.no.line("multiple ai-rate-limiting-advanced plugins with the namespace 'openai' have different counter syncing configurations", true, 5)
    end)
  end)
end