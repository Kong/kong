local helpers = require "spec.helpers"
local declarative = require "kong.db.declarative"
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy
local uuid = require("kong.tools.uuid").uuid

-- Note: include "off" strategy here as well
for _, strategy in helpers.all_strategies() do
  describe("db.dao #" .. strategy, function()
    local bp, db
    local consumer, service, service2, plugin, plugin2, acl
    local group = "The A Team"

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "plugins",
        "services",
        "consumers",
        "acls",
        "keyauth_credentials",
      })
      _G.kong.db = db

      consumer = bp.consumers:insert {
        username = "andru",
        custom_id = "donalds",
      }

      service = bp.services:insert {
        name = "abc",
        url = "http://localhost",
      }

      service2 = bp.services:insert {
        name = "def",
        url = "http://2-localhost",
      }

      plugin = bp.plugins:insert {
        enabled = true,
        name = "acl",
        service = service,
        config = {
          allow = { "*" },
        },
      }

      plugin2 = bp.plugins:insert {
        enabled = true,
        name = "rate-limiting",
        instance_name = 'rate-limiting-instance-1',
        service = service,
        config = {
          minute = 100,
          policy = "redis",
          redis = {
            host = "localhost"
          }
        },
      }
      -- Note: bp in off strategy returns service=id instead of a table
      plugin.service = {
        id = service.id
      }

      acl = bp.acls:insert {
        consumer = consumer,
        group = group,
      }
      -- Note: bp in off strategy returns consumer=id instead of a table
      acl.consumer = {
        id = consumer.id
      }

      if strategy == "off" then
        -- dc_blueprint stores entities in memory
        -- and helpers export it to file in start_kong
        -- since this test requires entities to load
        -- into current nginx's shdict instead of the
        -- Kong nginx started by start_kong, we need
        -- to manually load the config
        local cfg = bp.done()
        local dc = declarative.new_config(kong.configuration)
        local entities = assert(dc:parse_table(cfg))

        local kong_global = require("kong.global")
        local kong = _G.kong

        kong.worker_events = assert(kong_global.init_worker_events(kong.configuration))
        kong.cluster_events = assert(kong_global.init_cluster_events(kong.configuration, kong.db))
        kong.cache = assert(kong_global.init_cache(kong.configuration, kong.cluster_events, kong.worker_events))
        kong.core_cache = assert(kong_global.init_core_cache(kong.configuration, kong.cluster_events, kong.worker_events))

        assert(declarative.load_into_cache(entities))
      end
    end)

    lazy_teardown(function()
      db.acls:truncate()
      db.consumers:truncate()
      db.plugins:truncate()
      db.services:truncate()
      db.keyauth_credentials:truncate()
    end)

    it("select_by_cache_key()", function()
      local cache_key = kong.db.acls:cache_key(consumer.id, group)

      local read_acl, err = kong.db.acls:select_by_cache_key(cache_key)
      assert.is_nil(err)
      assert.same(acl, read_acl)

      -- cache_key = { "name", "route", "service", "consumer" },
      cache_key = kong.db.plugins:cache_key("acl", nil, service.id, nil)
      local read_plugin, err = kong.db.plugins:select_by_cache_key(cache_key)
      assert.is_nil(err)
      assert.same(plugin, read_plugin)

      cache_key = kong.db.plugins:cache_key("rate-limiting", nil, service.id, nil)
      read_plugin, err = kong.db.plugins:select_by_cache_key(cache_key)
      assert.is_nil(err)
      assert.same(plugin2, read_plugin)
    end)

    it("page_for_route", function()
      local plugins_for_service, err = kong.db.plugins:page_for_service(service)
      assert.is_nil(err)
      assert.equal(2, #plugins_for_service)
      for _, read_plugin in ipairs(plugins_for_service) do
        if read_plugin.name == 'acl' then
          assert.same(plugin, read_plugin)
        elseif read_plugin.name == 'rate-limiting' then
          assert.same(plugin2, read_plugin)
        end
      end
    end)

    it("select_by_instance_name", function()
      local read_plugin, err = kong.db.plugins:select_by_instance_name(plugin2.instance_name)
      assert.is_nil(err)
      assert.same(plugin2, read_plugin)
    end)

    it("update_by_instance_name", function()
      local newhost = "newhost"
      local updated_plugin = cycle_aware_deep_copy(plugin2)
      updated_plugin.config.redis.host = newhost
      updated_plugin.config.redis_host = newhost

      local read_plugin, err = kong.db.plugins:update_by_instance_name(plugin2.instance_name, updated_plugin)
      assert.is_nil(err)
      assert.same(updated_plugin, read_plugin)
    end)

    it("upsert_by_instance_name", function()
      -- existing plugin upsert (update part of upsert)
      local newhost = "newhost"
      local updated_plugin = cycle_aware_deep_copy(plugin2)
      updated_plugin.config.redis.host = newhost
      updated_plugin.config.redis_host = newhost

      local read_plugin, err = kong.db.plugins:upsert_by_instance_name(plugin2.instance_name, updated_plugin)
      assert.is_nil(err)
      assert.same(updated_plugin, read_plugin)

      -- new plugin upsert (insert part of upsert)
      local new_plugin_config = {
        id = uuid(),
        enabled = true,
        name = "rate-limiting",
        instance_name = 'rate-limiting-instance-2',
        service = service2,
        config = {
          minute = 200,
          policy = "redis",
          redis = {
            host = "new-host-2"
          }
        },
      }

      local read_plugin, err = kong.db.plugins:upsert_by_instance_name(new_plugin_config.instance_name, new_plugin_config)
      assert.is_nil(err)
      assert.same(new_plugin_config.id, read_plugin.id)
      assert.same(new_plugin_config.instance_name, read_plugin.instance_name)
      assert.same(new_plugin_config.service.id, read_plugin.service.id)
      assert.same(new_plugin_config.config.minute, read_plugin.config.minute)
      assert.same(new_plugin_config.config.redis.host, read_plugin.config.redis.host)
      assert.same(new_plugin_config.config.redis.host, read_plugin.config.redis_host) -- legacy field is included
    end)

    it("keyauth_credentials can be deleted or selected before run ttl cleanup in background timer", function()
      local key = uuid()
      local original_keyauth_credentials = bp.keyauth_credentials:insert({
        consumer = { id = consumer.id },
        key = key,
      }, { ttl = 5 })

      -- wait for 5 seconds.
      ngx.sleep(5)

      -- select or delete keyauth_credentials after ttl expired.
      local expired_keyauth_credentials
      helpers.wait_until(function()
        expired_keyauth_credentials = kong.db.keyauth_credentials:select_by_key(key)
        return not expired_keyauth_credentials
      end, 1)
      assert.is_nil(expired_keyauth_credentials)
      kong.db.keyauth_credentials:delete_by_key(key)

      -- select or delete keyauth_credentials with skip_ttl=true after ttl expired.
      expired_keyauth_credentials = kong.db.keyauth_credentials:select_by_key(key, { skip_ttl = true })
      assert.not_nil(expired_keyauth_credentials)
      assert.same(expired_keyauth_credentials.id, original_keyauth_credentials.id)
      kong.db.keyauth_credentials:delete_by_key(key, { skip_ttl = true })

      -- check again
      expired_keyauth_credentials = kong.db.keyauth_credentials:select_by_key(key, { skip_ttl = true })
      assert.is_nil(expired_keyauth_credentials)
    end)
  end)
end

