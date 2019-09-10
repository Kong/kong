local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local pl_utils = require "pl.utils"

local fmt = string.format

local KAFKA_HOST = "127.0.0.1"
local KAFKA_PORT = 9092
local BOOTSTRAP_SERVERS = { { host = KAFKA_HOST, port = KAFKA_PORT } }

local ZOOKEEPER_HOST = "127.0.0.1"
local ZOOKEEPER_PORT = 2181

-- We use kafka's command-line utilities on these specs. As a result,
-- this timeout must be higher than the time it takes to load up the Kafka
-- environment from the command line. Otherwise async tests might pass
-- when they should not.
local FLUSH_TIMEOUT_MS = 8000 -- milliseconds

local FLUSH_TIMEOUT = FLUSH_TIMEOUT_MS / 1000 -- seconds
local FLUSH_BUFFER_SIZE = 3

local MAX_TIMEOUT = 10 -- seconds

local timeout_command
do
  local ok, ret = pl_utils.executeex("type timeout")
  if ok and ret == 0 then
    timeout_command = "timeout"
  else
    local ok, ret = pl_utils.executeex("type gtimeout")
    if ok and ret == 0 then
      timeout_command = "gtimeout"
    else
      error("No timeout command available. Install coreutils")
    end
  end
end


local function execute(cmd)
  local ok, ret, stdout, stderr = pl_utils.executeex(cmd)
  if not ok or ret ~= 0 then
    return nil, "The commmand: \n\n" .. cmd ..
                "\n\nFailed with return value: [" .. tostring(ret) ..
                "] and the following error message:\n\n" .. stderr
  end
  return stdout
end


local function kafka_create_topic()
  -- The random string at the end is to avoid clashes with previous runs of the spec
  local topic = "kong-log-" .. utils.random_string()
  local cmd = fmt("kafka-topics.sh --create --zookeeper %s:%d --partitions 1 --replication-factor 1 --topic %s",
                   ZOOKEEPER_HOST, ZOOKEEPER_PORT, topic)
  assert(execute(cmd))
  return topic
end


local function kafka_read_topic(topic, number_of_messages, timeout)
  local cmd = fmt("%s %ds kafka-console-consumer.sh --bootstrap-server %s:%d --from-beginning --topic %s --max-messages %d",
                  timeout_command, timeout, KAFKA_HOST, KAFKA_PORT, topic, number_of_messages)
  return execute(cmd)
end


for _, strategy in helpers.each_strategy() do
  describe("Plugin: kafka-log (access)", function()
    local proxy_client
    local admin_client
    local sync_topic
    local async_timeout_topic
    local async_size_topic
    local service

    setup(function()
      local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        }, { "kafka-log" })

      service = bp.services:insert {
        name = "mock-service",
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = helpers.mock_upstream_protocol,
      }

      local sync_route = bp.routes:insert {
        protocols = { "http" },
        hosts = { "sync-host.test" },
        service = { id = service.id },
      }

      local async_timeout_route = bp.routes:insert {
        protocols = { "http" },
        hosts = { "async-timeout-host.test" },
        service = { id = service.id },
      }

      local async_size_route = bp.routes:insert {
        protocols = { "http" },
        hosts = { "async-size-host.test" },
        service = { id = service.id },
      }

      sync_topic = kafka_create_topic()
      async_timeout_topic = kafka_create_topic()
      async_size_topic = kafka_create_topic()

      bp.plugins:insert {
        name = "kafka-log",
        route = { id = sync_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = false,
          topic = sync_topic,
        }
      }

      bp.plugins:insert {
        name = "kafka-log",
        route = { id = async_timeout_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = true,
          producer_async_flush_timeout = FLUSH_TIMEOUT_MS,
          topic = async_timeout_topic,
        }
      }

      bp.plugins:insert {
        name = "kafka-log",
        route = { id = async_size_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = true,
          producer_async_flush_timeout = FLUSH_TIMEOUT_MS * 1000, -- never timeout
          producer_async_buffering_limits_messages_in_memory = FLUSH_BUFFER_SIZE,
          topic = async_size_topic,
        }
      }

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,kafka-log",
      })
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
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
        local res = proxy_client:get("/status/200", {
          headers = { host = "sync-host.test" },
        })
        assert.res_status(200, res)

        local str = assert(kafka_read_topic(sync_topic, 1, MAX_TIMEOUT))

        local json = cjson.decode(str)
        assert.equal(json.request.uri, "/status/200")
        assert.equal(json.service.id, service.id)
        assert.equal(json.response.status, 200)
      end)
    end)

    describe("async mode", function()
      it("sends batched data, after waiting long enough", function()
        local res = proxy_client:get("/status/200", {
          headers = { host = "async-timeout-host.test" },
        })
        assert.res_status(200, res)

        -- test that the request was not sent immediately
        local str, err = kafka_read_topic(async_timeout_topic, 1, FLUSH_TIMEOUT / 5)
        assert.is_nil(str)
        assert.match("Failed with return value: %[124%]", err)

        ngx.sleep(FLUSH_TIMEOUT * 2)

        local str = assert(kafka_read_topic(async_timeout_topic, 1, MAX_TIMEOUT))

        local json = cjson.decode(str)
        assert.equal(json.request.uri, "/status/200")
        assert.equal(json.service.id, service.id)
        assert.equal(json.response.status, 200)
      end)

      it("sends batched data, after batching a certain number of messages", function()
        for i = 1, FLUSH_BUFFER_SIZE + 1 do
          local res = proxy_client:get("/status/200", {
            headers = { host = "async-size-host.test" },
          })
          assert.res_status(200, res)
          if i == FLUSH_BUFFER_SIZE + 1 then
            -- Test that you get all previously inserted items on the list after inserting the n+1 one
            assert(kafka_read_topic(async_size_topic, FLUSH_BUFFER_SIZE, MAX_TIMEOUT))

          else
            -- If you are not on the n + 1 item, you should see no traffic
            local str, err = kafka_read_topic(async_size_topic, 1, 1)
            assert.is_nil(str)
            assert.match("Failed with return value: %[124%]", err)
          end
        end
      end)
    end)
  end)
end
