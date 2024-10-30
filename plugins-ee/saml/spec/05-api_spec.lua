-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("when creating plugin instance", function()
    describe("with redis configuration", function()
      describe("when using old fields shorthands", function()
        local admin_client
        local bp, db
        local route

        lazy_setup(function()
          bp, db = helpers.get_db_utils(strategy, {
            "routes",
            "services",
            "plugins",
          }, {
            "saml",
          })

          local service = bp.services:insert()

          route = bp.routes:insert {
            hosts      = { "test1.test" },
            protocols  = { "http", "https" },
            service    = service,
          }

          assert(helpers.start_kong({
            database   = strategy,
            plugins    = "bundled,saml",
            nginx_conf = "spec/fixtures/custom_nginx.template",
          }))

          admin_client = helpers.admin_client()
        end)

        lazy_teardown(function()
          if admin_client then
            admin_client:close()
          end

          helpers.stop_kong()
        end)

        after_each(function()
          db:truncate("plugins")
        end)

        it("should save host/port", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "saml",
              route = { id = route.id },
              config = {
                idp_sso_url = "http://example.com",
                issuer = "test",
                session_secret = "testtesttesttesttesttesttesttest",
                assertion_consumer_path = "/test",
                validate_assertion_signature = false,
                session_storage = "redis",
                session_redis_host = "localhost",
                session_redis_port = 1234,
                session_redis_prefix = "abc_",
                session_redis_username = "test",
                session_redis_password = "test",
                session_redis_connect_timeout = 101,
                session_redis_read_timeout = 102,
                session_redis_send_timeout = 103,
                session_redis_ssl = true,
                session_redis_ssl_verify = true,
                session_redis_server_name = "redis.name.example",
                session_redis_cluster_max_redirections = 7,
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))

          -- "OLD" config
          assert.same("localhost", body.config.session_redis_host)
          assert.same(1234, body.config.session_redis_port)
          assert.same("abc_", body.config.session_redis_prefix)
          assert.same("test", body.config.session_redis_username)
          assert.same("test", body.config.session_redis_password)
          assert.same(101, body.config.session_redis_connect_timeout)
          assert.same(102, body.config.session_redis_read_timeout)
          assert.same(103, body.config.session_redis_send_timeout)
          assert.same(true, body.config.session_redis_ssl)
          assert.same(true, body.config.session_redis_ssl_verify)
          assert.same("redis.name.example", body.config.session_redis_server_name)
          assert.same(7, body.config.session_redis_cluster_max_redirections)

          -- "NEW" (v2) config
          assert.same("localhost", body.config.redis.host)
          assert.same(1234, body.config.redis.port)
          assert.same("abc_", body.config.redis.prefix)
          assert.same("test", body.config.redis.username)
          assert.same("test", body.config.redis.password)
          assert.same(101, body.config.redis.connect_timeout)
          assert.same(102, body.config.redis.read_timeout)
          assert.same(103, body.config.redis.send_timeout)
          assert.same(true, body.config.redis.ssl)
          assert.same(true, body.config.redis.ssl_verify)
          assert.same("redis.name.example", body.config.redis.server_name)
          assert.same(7, body.config.redis.cluster_max_redirections)
        end)

        it("should save cluster nodes", function()
          local cluster_nodes_config = {
            {
              ip = "redis-node-1",
              port = 6379,
            },
            {
              ip = "redis-node-2",
              port = 6380,
            },
            {
              ip = "127.0.0.1",
              port = 6381,
            },
          }
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "saml",
              route = { id = route.id },
              config = {
                idp_sso_url = "http://example.com",
                issuer = "test",
                session_secret = "testtesttesttesttesttesttesttest",
                assertion_consumer_path = "/test",
                validate_assertion_signature = false,
                session_storage = "redis",
                session_redis_cluster_nodes = cluster_nodes_config
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))

          -- "OLD" config
          assert.same(cluster_nodes_config, body.config.session_redis_cluster_nodes)

          -- "NEW" (v2) config
          assert.same(cluster_nodes_config, body.config.redis.cluster_nodes)
        end)

        it("should save socket", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "saml",
              route = { id = route.id },
              config = {
                idp_sso_url = "http://example.com",
                issuer = "test",
                session_secret = "testtesttesttesttesttesttesttest",
                assertion_consumer_path = "/test",
                validate_assertion_signature = false,
                session_storage = "redis",
                session_redis_socket = "socket-1"
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))

          -- "OLD" config
          assert.same("socket-1", body.config.session_redis_socket)

          -- "NEW" (v2) config
          assert.same("socket-1", body.config.redis.socket)
        end)

        it("accepts empty config - defaults to host/port", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "saml",
              route = { id = route.id },
              config = {
                idp_sso_url = "http://example.com",
                issuer = "test",
                session_secret = "testtesttesttesttesttesttesttest",
                assertion_consumer_path = "/test",
                validate_assertion_signature = false,
                session_storage = "redis",
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.same("127.0.0.1", body.config.redis.host)
          assert.same(6379, body.config.redis.port)
        end)

        it("accepts only partial config with host defined - port fallbacks to default", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "saml",
              route = { id = route.id },
              config = {
                idp_sso_url = "http://example.com",
                issuer = "test",
                session_secret = "testtesttesttesttesttesttesttest",
                assertion_consumer_path = "/test",
                validate_assertion_signature = false,
                session_storage = "redis",
                redis = {
                  host = "example"
                }
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))
          assert.same("example", body.config.redis.host)
          assert.same(6379, body.config.redis.port)
        end)

        it("doesn't accept empty config with explicit nulls", function()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "saml",
              route = { id = route.id },
              config = {
                idp_sso_url = "http://example.com",
                issuer = "test",
                session_secret = "testtesttesttesttesttesttesttest",
                assertion_consumer_path = "/test",
                validate_assertion_signature = false,
                session_storage = "redis",
                redis = {
                  host = ngx.null,
                  port = ngx.null
                }
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(400, res))

           assert.same("No redis config provided", body.fields['@entity'][1])
        end)

        it("should save all configuration both host/port and cluster_nodes", function()
          local cluster_nodes_config = {
            {
              ip = "redis-node-1",
              port = 6379,
            },
            {
              ip = "redis-node-2",
              port = 6380,
            },
            {
              ip = "127.0.0.1",
              port = 6381,
            },
          }
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "saml",
              route = { id = route.id },
              config = {
                idp_sso_url = "http://example.com",
                issuer = "test",
                session_secret = "testtesttesttesttesttesttesttest",
                assertion_consumer_path = "/test",
                validate_assertion_signature = false,
                session_storage = "redis",
                session_redis_host = "localhost",
                session_redis_port = 7123,
                session_redis_cluster_nodes = cluster_nodes_config
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = cjson.decode(assert.res_status(201, res))

          -- "OLD" config
          assert.same("localhost", body.config.session_redis_host)
          assert.same(7123, body.config.session_redis_port)
          assert.same(cluster_nodes_config, body.config.session_redis_cluster_nodes)

          -- "NEW" (v2) config
          assert.same("localhost", body.config.redis.host)
          assert.same(7123, body.config.redis.port)
          assert.same(cluster_nodes_config, body.config.redis.cluster_nodes)
        end)

        it("should allow to configure all of the options", function ()
          local res = assert(admin_client:send {
            method  = "POST",
            path    = "/plugins",
            body    = {
              name  = "saml",
              route = { id = route.id },
              config = {
                idp_sso_url = "http://example.com",
                issuer = "test",
                session_secret = "testtesttesttesttesttesttesttest",
                assertion_consumer_path = "/test",
                validate_assertion_signature = false,
                session_storage = "redis",
                redis = {
                  host = "example.com",
                  port = 6380,
                  cluster_nodes = {
                    {
                      ip = "redis-node-1",
                      port = 6379,
                    },
                    {
                      ip = "redis-node-2",
                      port = 6380,
                    },
                    {
                      ip = "127.0.0.1",
                      port = 6381,
                    },
                  },
                  sentinel_nodes = {
                    {
                      host = "redis-sentinel-node-1",
                      port = 6379,
                    },
                    {
                      host = "redis-sentinel-node-2",
                      port = 6380,
                    },
                    {
                      host = "redis-sentinel-node-3",
                      port = 6381,
                    },
                  },
                  sentinel_role = "master",
                  sentinel_master = "mymaster"
                }
              },
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          assert.res_status(201, res)
        end)
      end)
    end)
  end)
end
