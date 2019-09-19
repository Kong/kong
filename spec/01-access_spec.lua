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


local function kafka_create_topic(str)
  -- The random string at the end is to avoid clashes with previous runs of the spec
  local topic = "kong-upstream-" .. str .. utils.random_string()
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
  describe("Plugin: kafka-upstream (access) [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local sync_topic
    local async_timeout_topic
    local async_size_topic

    setup(function()
      local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        }, { "kafka-upstream" })

      local sync_route = bp.routes:insert {
        hosts = { "sync-host.test" },
      }

      local async_timeout_route = bp.routes:insert {
        hosts = { "async-timeout-host.test" },
      }

      local async_size_route = bp.routes:insert {
        hosts = { "async-size-host.test" },
      }

      sync_topic          = kafka_create_topic("sync")
      async_timeout_topic = kafka_create_topic("async-timeout")
      async_size_topic    = kafka_create_topic("async-size")

      bp.plugins:insert {
        name = "kafka-upstream",
        route = { id = sync_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = false,
          topic = sync_topic,
        }
      }

      bp.plugins:insert {
        name = "kafka-upstream",
        route = { id = async_timeout_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = true,
          producer_async_flush_timeout = FLUSH_TIMEOUT_MS,
          topic = async_timeout_topic,
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
          topic = async_size_topic,
        }
      }

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,kafka-upstream",
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
        local uri = "/path?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { foo = "bar" },
        })
        assert.res_status(200, res)

        local str = assert(kafka_read_topic(sync_topic, 1, MAX_TIMEOUT))
        local json = cjson.decode(str)

        assert.is_nil(json.method)
        assert.is_nil(json.headers)
        assert.is_nil(json.uri)
        assert.is_nil(json.uri_args)
        assert.equals('{"foo":"bar"}', json.body)
        assert.same({ foo = "bar" }, json.body_args)
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
        assert.res_status(200, res)

        -- test that the request was not sent immediately
        local str, err = kafka_read_topic(async_timeout_topic, 1, FLUSH_TIMEOUT / 5)
        assert.is_nil(str)
        assert.match("Failed with return value: %[124%]", err)

        ngx.sleep(FLUSH_TIMEOUT * 2)

        local str = assert(kafka_read_topic(async_timeout_topic, 1, MAX_TIMEOUT))
        local json = cjson.decode(str)

        assert.equals("POST", json.method)
        assert.same("async-timeout-host.test", json.headers.host)
        assert.equals(uri, json.uri)
        assert.same({ key1 = "value1", key2 = "value2" }, json.uri_args)
        assert.equals('{"foo":"bar"}', json.body)
        assert.same({}, json.body_args) -- empty because the content type is text/plain; there's no parsing
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
