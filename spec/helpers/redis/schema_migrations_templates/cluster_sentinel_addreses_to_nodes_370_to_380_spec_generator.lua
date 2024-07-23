-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local assert = require "luassert"
local busted = require "busted"
local cjson = require "cjson"
local uh = require "spec.upgrade_helpers"
local pl_tablex = require "pl.tablex"


local function test_plugin_migrations(test_configuration, minimum_supported_version)
  if uh.database_type() == 'postgres' then
    local handler = uh.get_busted_handler(minimum_supported_version)
    handler("[" .. test_configuration.plugin_name .. "] plugin migration - (cluster/sentinel)_addresses to (cluster_sentinel)_nodes", function()
      local route1_name = "test1"
      local route2_name = "test2"

      busted.describe("when redis is set to connect to redis cluster", function()
        local cluster_node1 = { ip = "127.0.0.1", port = 26379 }
        local cluster_node2 = { ip = "127.0.0.1", port = 26380 }
        local cluster_node3 = { ip = "127.0.0.2", port = 26381 }
        local cluster_nodes = { cluster_node1, cluster_node2, cluster_node3 }
        local cluster_addresses = {
          cluster_node1.ip .. ":" .. cluster_node1.port,
          cluster_node2.ip .. ":" .. cluster_node2.port,
          cluster_node3.ip .. ":" .. cluster_node3.port,
        }

        busted.lazy_setup(function()
          assert(uh.start_kong())
        end)

        busted.lazy_teardown(function ()
          assert(uh.stop_kong())
        end)

        uh.setup(function ()
          local admin_client = assert(uh.admin_client())
          local res = assert(admin_client:send {
            method = "POST",
            path = "/routes/",
            body = {
                name  = route1_name,
                hosts = { "test1.test" },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)

          res = assert(admin_client:send {
            method = "POST",
            path = "/routes/" .. route1_name .. "/plugins/",
            body = {
              name = test_configuration.plugin_name,
              config = pl_tablex.merge(
                test_configuration.plugin_config,
                { redis = {
                  cluster_addresses = cluster_addresses
                } },
                true
              )
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.equal(test_configuration.plugin_name, body.name)
          assert.same(cluster_addresses, body.config.redis.cluster_addresses)
          assert.is_nil(body.config.redis.cluster_nodes)
          admin_client:close()
        end)

        uh.new_after_finish("has updated [" .. test_configuration.plugin_name .. "] redis configuration - cluster_addresses were translated to cluster_nodes", function ()
          local admin_client = assert(uh.admin_client())
          local res = assert(admin_client:send {
            method = "GET",
            path = "/routes/" .. route1_name .. "/plugins/",
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.equal(1, #body.data)
          assert.equal(test_configuration.plugin_name, body.data[1].name)
          assert.same(cluster_nodes, body.data[1].config.redis.cluster_nodes)
          assert.same(cluster_addresses, body.data[1].config.redis.cluster_addresses)

          admin_client:close()
        end)
      end)

      busted.describe("when redis is set to connect to redis sentinel", function()
        local sentinel_node1 = { host = "localhost1", port = 26379 }
        local sentinel_node2 = { host = "localhost2", port = 26380 }
        local sentinel_node3 = { host = "localhost3", port = 26381 }
        local sentinel_nodes = { sentinel_node1, sentinel_node2, sentinel_node3 }
        local sentinel_addresses = {
          sentinel_node1.host .. ":" .. sentinel_node1.port,
          sentinel_node2.host .. ":" .. sentinel_node2.port,
          sentinel_node3.host .. ":" .. sentinel_node3.port,
        }

        busted.lazy_setup(function()
          assert(uh.start_kong())
        end)

        busted.lazy_teardown(function ()
          assert(uh.stop_kong())
        end)

        uh.setup(function ()
          local admin_client = assert(uh.admin_client())
          local res = assert(admin_client:send {
            method = "POST",
            path = "/routes/",
            body = {
              name  = route2_name,
              hosts = { "test2.test" },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)

          res = assert(admin_client:send {
            method = "POST",
            path = "/routes/" .. route2_name .. "/plugins/",
            body = {
              name = test_configuration.plugin_name,
              config = pl_tablex.merge(
                test_configuration.plugin_config,
                { redis = {
                  sentinel_role = "master",
                  sentinel_master = "localhost1",
                  sentinel_addresses = sentinel_addresses
                } },
                true
              )
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.equal(test_configuration.plugin_name, body.name)
          assert.same(sentinel_addresses, body.config.redis.sentinel_addresses)
          assert.is_nil(body.config.redis.cluster_nodes)
          admin_client:close()
        end)

        uh.new_after_finish("has updated [" .. test_configuration.plugin_name .. "] redis configuration - sentinel_addresses were translated to sentinel_nodes", function ()
          local admin_client = assert(uh.admin_client())
          local res = assert(admin_client:send {
            method = "GET",
            path = "/routes/" .. route2_name .. "/plugins/",
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.equal(1, #body.data)
          assert.equal(test_configuration.plugin_name, body.data[1].name)
          assert.same(sentinel_nodes, body.data[1].config.redis.sentinel_nodes)
          assert.same(sentinel_addresses, body.data[1].config.redis.sentinel_addresses)

          admin_client:close()
        end)
      end)
    end)
  end
end

return {
  test_plugin_migrations = test_plugin_migrations
}
