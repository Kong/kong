-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local ssl_helpers = require "spec.cert_helpers"

local KAFKA_HOST = "broker"
local KAFKA_PORT = 9092
local BOOTSTRAP_SERVERS = { { host = KAFKA_HOST, port = KAFKA_PORT } }

local KAFKA_SASL_PORT = 19093
local BOOTSTRAP_SASL_SERVERS = { { host = KAFKA_HOST, port = KAFKA_SASL_PORT } }

local KAFKA_SSL_PORT = 29093
local BOOTSTRAP_SSL_SERVERS = { { host = KAFKA_HOST, port = KAFKA_SSL_PORT } }

local KAFKA_SASL_SSL_PORT = 9093
local BOOTSTRAP_SASL_SSL_SERVERS = { { host = KAFKA_HOST, port = KAFKA_SASL_SSL_PORT } }

-- We use kafka's command-line utilities on these specs. As a result,
-- this timeout must be higher than the time it takes to load up the Kafka
-- environment from the command line. Otherwise async tests might pass
-- when they should not.
local FLUSH_TIMEOUT_MS = 8000 -- milliseconds

local FLUSH_BUFFER_SIZE = 3

for _, strategy in helpers.each_strategy() do
  describe("Plugin: kafka-upstream (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client

    setup(function()
      local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
          "certificates",
        }, { "kafka-upstream" })

      local sync_route = bp.routes:insert {
        hosts = { "sync-host.test" },
      }

      local sync_sasl_route = bp.routes:insert {
        hosts = { "sync-sasl-host.test" },
      }

      local sync_sasl_ssl_route = bp.routes:insert {
        hosts = { "sync-sasl-ssl-host.test" },
      }

      local sync_mtls_route = bp.routes:insert {
        hosts = { "sync-mtls-host.test" },
      }

      local async_timeout_route = bp.routes:insert {
        hosts = { "async-timeout-host.test" },
      }

      local async_size_route = bp.routes:insert {
        hosts = { "async-size-host.test" },
      }

      local cert = bp.certificates:insert({
        cert = ssl_helpers.cert,
        key = ssl_helpers.key 
      })

      bp.plugins:insert {
        name = "kafka-upstream",
        route = { id = sync_mtls_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SSL_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
          security = {
            ssl = false,
            certificate_id = cert.id
          }
        }
      }

      bp.plugins:insert {
        name = "kafka-upstream",
        route = { id = sync_sasl_ssl_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SASL_SSL_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
          authentication = {
            strategy = 'sasl',
            mechanism = 'PLAIN',
            user = 'admin',
            password = 'admin-secret'
          },
          security = {
            ssl = true,
            certificate_id = cert.id
          }
        }
      }

      bp.plugins:insert {
        name = "kafka-upstream",
        route = { id = sync_sasl_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SASL_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
          authentication = {
            strategy = 'sasl',
            mechanism = 'PLAIN',
            user = 'admin',
            password = 'admin-secret'
          },
          -- TODO: This shouldn't be needed. However if not set this tries to query SSL_SASL on the kafka side if unset
          --       Verify if this a genuine bug or just a sideeffect of the lua-rest-kafka lib not being upgraded
          security = {
            ssl = false
          }
        }
      }

      bp.plugins:insert {
        name = "kafka-upstream",
        route = { id = sync_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
        }
      }

      bp.plugins:insert {
        name = "kafka-upstream",
        route = { id = async_timeout_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = true,
          producer_async_flush_timeout = FLUSH_TIMEOUT_MS,
          topic = 'async_timeout_topic',
          forward_method = true,
          forward_uri = true,
          forward_headers = true,
        }
      }

      bp.plugins:insert {
        name = "kafka-upstream",
        route = { id = async_size_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = true,
          producer_async_flush_timeout = FLUSH_TIMEOUT_MS * 1000, -- never timeout
          producer_async_buffering_limits_messages_in_memory = FLUSH_BUFFER_SIZE,
          topic = 'async_size_topic',
        }
      }

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,kafka-upstream",
      })
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
      
    end)
    lazy_setup(function()
      -- Execute before tests to setup topics in kafka
      local uri = "/path?key1=value1&key2=value2"
      local res = proxy_client:post(uri, {
        headers = {
          host = "sync-host.test",
          ["Content-Type"] = "application/json",
        },
        body = { foo = "bar" },
      })
      res.status = 200
      assert.res_status(200, res)
      local uri = "/path?key1=value1&key2=value2"
      local res = proxy_client:post(uri, {
        headers = {
          host = "async-timeout-host.test",
          ["Content-Type"] = "application/json",
        },
        body = { foo = "bar" },
      })
      res.status = 200
      assert.res_status(200, res)
      local uri = "/path?key1=value1&key2=value2"
      local res = proxy_client:post(uri, {
        headers = {
          host = "async-size-host.test",
          ["Content-Type"] = "application/json",
        },
        body = { foo = "bar" },
      })
      res.status = 200
      assert.res_status(200, res)
      -- wait for kafka to catch up
      ngx.sleep(10)
    end)
    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
    end)


    teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      if admin_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("sync mode", function()
      it("sends data immediately after a request", function()
        local uri = "/path?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { foo = "bar" },
        })
        local raw_body = res:read_body()
        local body = cjson.decode(raw_body)
        assert.res_status(200, res)
        assert(body.message, "message sent")
      end)
    end)

    describe("sasl auth", function()
      it("authenticates with sasl credentials [no ssl]", function()
        local uri = "/path?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-sasl-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { foo = "bar" },
        })
        local raw_body = res:read_body()
        local body = cjson.decode(raw_body)
        assert.res_status(200, res)
        assert(body.message, "message sent")
      end)

      it("authenticates with sasl credentials [ssl]", function()
        local uri = "/path?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-sasl-ssl-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { foo = "bar" },
        })
        local raw_body = res:read_body()
        local body = cjson.decode(raw_body)
        assert.res_status(200, res)
        assert(body.message, "message sent")
      end)
    end)

    describe("mtls", function()
      it("authenticates with certificates", function()
        local uri = "/path?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-sasl-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { foo = "bar" },
        })
        local raw_body = res:read_body()
        local body = cjson.decode(raw_body)
        assert.res_status(200, res)
        assert(body.message, "message sent")
      end)
    end)

    describe("async mode", function()
      it("sends batched data, after waiting long enough", function()
        local uri = "/path?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "async-timeout-host.test",
            ["Content-Type"] = "text/plain",
          },
          body = '{"foo":"bar"}',
        })
        local raw_body = res:read_body()
        local body = cjson.decode(raw_body)
        assert.res_status(200, res)
        assert(body.message, "message sent")
      end)

      it("sends batched data, after batching a certain number of messages", function()
        local uri = "/path?key1=value1&key2=value2"
        for i = 1, FLUSH_BUFFER_SIZE + 1 do
          local res = proxy_client:post(uri, {
            headers = {
              host = "async-size-host.test",
              ["Content-Type"] = "application/json",
            },
            body = { foo = "bar" },
          })
          local raw_body = res:read_body()
          local body = cjson.decode(raw_body)
          assert.res_status(200, res)
          assert(body.message, "message sent")
        end
      end)
    end)
  end)
end
