-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local kill = ngx.thread.kill

local CONFLUENT_HOST = os.getenv("KONG_SPEC_TEST_CONFLUENT_HOST")
local CONFLUENT_PORT = tonumber(os.getenv("KONG_SPEC_TEST_CONFLUENT_PORT"))
local BOOTSTRAP_SERVERS = { { host = CONFLUENT_HOST, port = CONFLUENT_PORT } }
local CONFLUENT_CLUSTER_API_KEY = os.getenv("KONG_SPEC_TEST_CONFLUENT_CLUSTER_API_KEY")
local CONFLUENT_CLUSTER_API_SECRET = os.getenv("KONG_SPEC_TEST_CONFLUENT_CLUSTER_API_SECRET")

local FLUSH_BATCH_SIZE = 3


-- We use kafka's command-line utilities on these specs. As a result,
-- this timeout must be higher than the time it takes to load up the Kafka
-- environment from the command line. Otherwise async tests might pass
-- when they should not.
local FLUSH_TIMEOUT_MS = 8000 -- milliseconds


for _, strategy in helpers.all_strategies() do
  describe("Plugin: confluent (access) [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        }, { "confluent" })

      local sync_route = bp.routes:insert {
        hosts = { "sync-host.test" },
      }
      local async_route = bp.routes:insert {
        hosts = { "async-host.test" },
      }
      local async_size_route = bp.routes:insert {
        hosts = { "async-size-host.test" },
      }

      assert(CONFLUENT_HOST and CONFLUENT_PORT and CONFLUENT_CLUSTER_API_KEY and CONFLUENT_CLUSTER_API_SECRET,
        "Must set environment variables: KONG_SPEC_TEST_CONFLUENT_HOST, KONG_SPEC_TEST_CONFLUENT_PORT, KONG_SPEC_TEST_CONFLUENT_CLUSTER_API_KEY, KONG_SPEC_TEST_CONFLUENT_CLUSTER_API_SECRET")
      bp.plugins:insert {
        name = "confluent",
        route = { id = sync_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = false,
          topic = 'kong-test',
          cluster_api_key = CONFLUENT_CLUSTER_API_KEY,
          cluster_api_secret = CONFLUENT_CLUSTER_API_SECRET,
        }
      }

      bp.plugins:insert {
        name = "confluent",
        route = { id = async_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = true,
          producer_async_flush_timeout = FLUSH_TIMEOUT_MS,
          topic = 'kong-test',
          forward_method = true,
          forward_uri = true,
          forward_headers = true,
          cluster_api_key = CONFLUENT_CLUSTER_API_KEY,
          cluster_api_secret = CONFLUENT_CLUSTER_API_SECRET,
        }
      }

      bp.plugins:insert {
        name = "confluent",
        route = { id = async_size_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = true,
          producer_async_flush_timeout = FLUSH_TIMEOUT_MS * 1000, -- never timeout
          producer_request_limits_messages_per_request = FLUSH_BATCH_SIZE,
          topic = 'kong-test',
          cluster_api_key = CONFLUENT_CLUSTER_API_KEY,
          cluster_api_secret = CONFLUENT_CLUSTER_API_SECRET,
        }
      }

      local fixtures = {
        dns_mock = helpers.dns_mock.new(),
      }

      if CONFLUENT_HOST ~= "broker" then
        -- dns mock needed to always redirect advertised host
        fixtures.dns_mock:A {
          name = "broker",
          address = CONFLUENT_HOST,
        }
      end

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,confluent",
      }, nil, nil, fixtures))
      proxy_client = helpers.proxy_client()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
    end)


    teardown(function()
      helpers.stop_kong()
    end)

    describe("sync mode", function()
      it("sends data immediately after a request", function()
        local uri = "/path?key1=value1&key2=value2&sync=0"
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

      it("concurrency with sync mode", function()
        local function co_send(proxy_client, uri)
          local res = proxy_client:post(uri, {
            headers = {
              host = "sync-host.test",
              ["Content-Type"] = "application/json",
            },
            body = { foo = "bar" },
          })

          local raw_body = res:read_body()
          return res, cjson.decode(raw_body)
        end

        local uri = "/path?key1=value1&key2=value2&sync=0"
        local pc1 = helpers.proxy_client()
        local pc2 = helpers.proxy_client()

        local co1 = spawn(co_send, pc1, uri)
        local co2 = spawn(co_send, pc2, uri)

        local _, res1, body1 = wait(co1)
        local _, res2, body2 = wait(co2)

        assert.res_status(200, res1)
        assert(body1.message, "message sent")
        assert.res_status(200, res2)
        assert(body2.message, "message sent")

        kill(co1)
        kill(co2)

        pc1:close()
        pc2:close()
      end)
    end)

    describe("async mode", function()
      it("sends batched data, after waiting long enough", function()
        local uri = "/path?key1=value1&key2=value2&async=1"
        local res = proxy_client:post(uri, {
          headers = {
            host = "async-host.test",
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
        for _ = 1, FLUSH_BATCH_SIZE + 1 do
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
