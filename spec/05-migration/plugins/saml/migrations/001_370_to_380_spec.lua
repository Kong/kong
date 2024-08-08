-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local uh = require "spec.upgrade_helpers"


if uh.database_type() == 'postgres' then
  -- SAML plugin does not exist on 2.8.x.x version
  local handler = uh.get_busted_handler("3.4.x.x")
  handler("saml plugin migration - move to shared redis schema", function()
    local route1_name = "test1"
    local route2_name = "test2"
    local route3_name = "test3"

    describe("when saml is configured - single Redis instance", function()
      lazy_setup(function()
        assert(uh.start_kong())
      end)

      lazy_teardown(function ()
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
            name = "saml",
            config = {
              issuer = "test",
              assertion_consumer_path = "/test",
              idp_sso_url = "http://example.com",
              validate_assertion_signature = false,
              session_secret = 'testtesttesttesttesttesttesttest',
              session_storage = 'redis',
              session_redis_prefix = 'some_prefix_',
              session_redis_host = 'localhost',
              session_redis_port = 7123,
              session_redis_username = 'test_username',
              session_redis_password = 'test_password',
              session_redis_connect_timeout = 1001,
              session_redis_read_timeout = 1002,
              session_redis_send_timeout = 1003,
              session_redis_ssl = true,
              session_redis_ssl_verify = true,
              session_redis_server_name = 'example.test',
              session_redis_cluster_max_redirections = 7,
            }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal("saml", body.name)
        assert.same('testtesttesttesttesttesttesttest', body.config.session_secret)
        assert.same('redis', body.config.session_storage)
        assert.same('some_prefix_', body.config.session_redis_prefix)
        assert.same('localhost', body.config.session_redis_host)
        assert.same(7123, body.config.session_redis_port)
        assert.same('test_username', body.config.session_redis_username)
        assert.same('test_password', body.config.session_redis_password)
        assert.same(1001, body.config.session_redis_connect_timeout)
        assert.same(1002, body.config.session_redis_read_timeout)
        assert.same(1003, body.config.session_redis_send_timeout)
        assert.same(true, body.config.session_redis_ssl)
        assert.same(true, body.config.session_redis_ssl_verify)
        assert.same('example.test', body.config.session_redis_server_name)
        assert.same(7, body.config.session_redis_cluster_max_redirections)
        admin_client:close()
      end)

      uh.new_after_finish("has updated rate-limiting-advanced redis configuration - connect,read,send are present", function ()
          local admin_client = assert(uh.admin_client())
          local res = assert(admin_client:send {
              method = "GET",
              path = "/routes/" .. route1_name .. "/plugins/",
          })
          local body = cjson.decode(assert.res_status(200, res))

          assert.equal(1, #body.data)
          assert.equal("saml", body.data[1].name)
          assert.same('testtesttesttesttesttesttesttest', body.data[1].config.session_secret)
          assert.same('redis', body.data[1].config.session_storage)
          assert.same('some_prefix_', body.data[1].config.redis.prefix)
          assert.same('localhost', body.data[1].config.redis.host)
          assert.same(7123, body.data[1].config.redis.port)
          assert.same('test_username', body.data[1].config.redis.username)
          assert.same('test_password', body.data[1].config.redis.password)
          assert.same(1001, body.data[1].config.redis.connect_timeout)
          assert.same(1002, body.data[1].config.redis.read_timeout)
          assert.same(1003, body.data[1].config.redis.send_timeout)
          assert.same(true, body.data[1].config.redis.ssl)
          assert.same(true, body.data[1].config.redis.ssl_verify)
          assert.same('example.test', body.data[1].config.redis.server_name)
          assert.same(7, body.data[1].config.redis.cluster_max_redirections)
          assert.same(ngx.null, body.data[1].config.redis.cluster_nodes)

          -- deprecated fields are also present in the response
          assert.same('some_prefix_', body.data[1].config.session_redis_prefix)
          assert.same('localhost', body.data[1].config.session_redis_host)
          assert.same(7123, body.data[1].config.session_redis_port)
          assert.same('test_username', body.data[1].config.session_redis_username)
          assert.same('test_password', body.data[1].config.session_redis_password)
          assert.same(1001, body.data[1].config.session_redis_connect_timeout)
          assert.same(1002, body.data[1].config.session_redis_read_timeout)
          assert.same(1003, body.data[1].config.session_redis_send_timeout)
          assert.same(true, body.data[1].config.session_redis_ssl)
          assert.same(true, body.data[1].config.session_redis_ssl_verify)
          assert.same('example.test', body.data[1].config.session_redis_server_name)
          assert.same(7, body.data[1].config.session_redis_cluster_max_redirections)
          assert.is_nil(body.data[1].config.session_redis_cluster_nodes)

          admin_client:close()
      end)
    end)

    describe("when saml is configured - cluster", function()
      local cluster_nodes = {
        { ip = '127.0.0.1', port = 6379 },
        { ip = '127.0.0.1', port = 6380 },
        { ip = '127.0.0.1', port = 6381 },
      }

      lazy_setup(function()
        assert(uh.start_kong())
      end)

      lazy_teardown(function ()
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
            name = "saml",
            config = {
              issuer = "test",
              assertion_consumer_path = "/test",
              idp_sso_url = "http://example.com",
              validate_assertion_signature = false,
              session_secret = 'testtesttesttesttesttesttesttest',
              session_storage = 'redis',
              session_redis_cluster_nodes = cluster_nodes
            }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal("saml", body.name)
        assert.same('testtesttesttesttesttesttesttest', body.config.session_secret)
        assert.same('redis', body.config.session_storage)
        assert.same(cluster_nodes, body.config.session_redis_cluster_nodes)
        admin_client:close()
      end)

      uh.new_after_finish("has updated rate-limiting-advanced redis configuration - connect,read,send are present", function ()
          local admin_client = assert(uh.admin_client())
          local res = assert(admin_client:send {
              method = "GET",
              path = "/routes/" .. route2_name .. "/plugins/",
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.equal(1, #body.data)
          assert.equal("saml", body.data[1].name)
          assert.same('testtesttesttesttesttesttesttest', body.data[1].config.session_secret)
          assert.same('redis', body.data[1].config.session_storage)
          assert.same(cluster_nodes, body.data[1].config.redis.cluster_nodes)
          assert.same(cluster_nodes, body.data[1].config.session_redis_cluster_nodes)

          admin_client:close()
      end)
    end)

    describe("when saml is configured with both cluster and single redis instance", function()
      local cluster_nodes = {
        { ip = '127.0.0.1', port = 6379 },
        { ip = '127.0.0.1', port = 6380 },
        { ip = '127.0.0.1', port = 6381 },
      }

      lazy_setup(function()
        assert(uh.start_kong())
      end)

      lazy_teardown(function ()
        assert(uh.stop_kong())
      end)

      uh.setup(function ()
        local admin_client = assert(uh.admin_client())
        local res = assert(admin_client:send {
          method = "POST",
          path = "/routes/",
          body = {
            name  = route3_name,
            hosts = { "test3.test" },
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)

        res = assert(admin_client:send {
          method = "POST",
          path = "/routes/" .. route3_name .. "/plugins/",
          body = {
            name = "saml",
            config = {
              issuer = "test",
              assertion_consumer_path = "/test",
              idp_sso_url = "http://example.com",
              validate_assertion_signature = false,
              session_secret = 'testtesttesttesttesttesttesttest',
              session_storage = 'redis',
              session_redis_host = 'localhost',
              session_redis_port = 7123,
              session_redis_cluster_nodes = cluster_nodes
            }
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        local body = cjson.decode(assert.res_status(201, res))
        assert.equal("saml", body.name)
        assert.same('testtesttesttesttesttesttesttest', body.config.session_secret)
        assert.same('redis', body.config.session_storage)
        assert.same('localhost', body.config.session_redis_host)
        assert.same(7123, body.config.session_redis_port)
        assert.same(cluster_nodes, body.config.session_redis_cluster_nodes)
        admin_client:close()
      end)

      uh.new_after_finish("has updated rate-limiting-advanced redis configuration - connect,read,send are present", function ()
          local admin_client = assert(uh.admin_client())
          local res = assert(admin_client:send {
              method = "GET",
              path = "/routes/" .. route3_name .. "/plugins/",
          })
          local body = cjson.decode(assert.res_status(200, res))
          assert.equal(1, #body.data)
          assert.equal("saml", body.data[1].name)
          assert.same('testtesttesttesttesttesttesttest', body.data[1].config.session_secret)
          assert.same('redis', body.data[1].config.session_storage)
          assert.same(cluster_nodes, body.data[1].config.redis.cluster_nodes)
          assert.same(cluster_nodes, body.data[1].config.session_redis_cluster_nodes)
          assert.same(ngx.null, body.data[1].config.redis.host)
          assert.same(ngx.null, body.data[1].config.redis.port)

          admin_client:close()
      end)
    end)
  end)
end
