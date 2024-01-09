-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local http = require "resty.http"
local cjson = require "cjson"
local pl_path = require "pl.path"

local KAFKA_HOST = "broker"
local KAFKA_PORT = 9092
local RESTY_PROXY_HOST = "rest-proxy"
local RESTY_PROXY_PORT = 8082

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

local FLUSH_BATCH_SIZE = 3

local function ssl_helpers()
  local fpath = require("spec.helpers").get_fixtures_path()
  -- two levels up
  local plugin_dir = pl_path.dirname(pl_path.dirname(pl_path.normpath(fpath)))

  -- Load certificate
  local f = assert(io.open(plugin_dir .. "/.pongo/kafka/keystore/certchain.crt"))
  local cert_data = f:read("*a")
  f:close()

  -- Load private key
  local f = assert(io.open(plugin_dir .. "/.pongo/kafka/keystore/privkey.key"))
  local key_data = f:read("*a")
  f:close()

  return {
    cert = cert_data,
    key = key_data
  }
end
ssl_helpers = ssl_helpers()

local function create_consumer(group_name, name)
  local client = helpers.http_client(RESTY_PROXY_HOST, RESTY_PROXY_PORT)

  local res = assert(client:send {
    method = "POST",
    path = "/consumers/" .. group_name,
    headers = {
      ["Content-Type"] = "application/vnd.kafka.v2+json",
      ["Accept"] = "application/vnd.kafka.v2+json",
    },
    body = '{"name": "' .. name .. '", "format": "binary", "auto.offset.reset": "earliest", "auto.commit.enable": "false"}',
  })

  local body = assert.res_status(200, res)
  local json = assert(cjson.decode(body))
  client:close()
  return json
end

local function subscribe_topic(base_uri, topic)
  local httpc = http.new()

  local res = assert(httpc:request_uri(base_uri .. "/subscription", {
    method = "POST",
    headers = {
      ["Content-Type"] = "application/vnd.kafka.v2+json",
    },
    body = '{"topics": ["' .. topic .. '"]}',
  }))
  assert.res_status(204, res)
  httpc:close()
end

local function consume_record(base_uri)
  local httpc = http.new()

  local res = assert(httpc:request_uri(base_uri .. "/records", {
    method = "GET",
    headers = {
      ["Accept"] = "application/vnd.kafka.binary.v2+json",
    },
  }))
  assert.same(200, res.status)
  local json = assert(cjson.decode(res.body))
  httpc:close()
  return json
end

local function delete_consumer(base_uri)
  local httpc = http.new()

  assert(httpc:request_uri(base_uri, {
    method = "DELETE",
    headers = {
      ["Content-Type"] = "application/vnd.kafka.v2+json",
    },
  }))

  httpc:close()
end

local function consume_all_records(base_uri)
  assert
    .with_timeout(10)
    .eventually(function()
      local record = consume_record(base_uri)
      return #record == 0
    end)
    .is_truthy()
end

local function wait_for_records(base_uri)
  local record
  assert
    .with_timeout(10)
    .eventually(function()
      record = consume_record(base_uri)
      return #record > 0
    end)
    .is_truthy()

  return record
end

for _, strategy in helpers.all_strategies() do
  describe("Plugin: kafka-log (access) [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
          "certificates",
        }, { "kafka-log" })

      local sync_route = bp.routes:insert {
        hosts = { "sync-host.test" },
      }

      local sync_sasl_plain_route = bp.routes:insert {
        hosts = { "sync-sasl-host.test" },
      }

      local sync_sasl_scram_sha256_route = bp.routes:insert {
        hosts = { "sync-sasl-scram-sha256-host.test" },
      }
      local sync_sasl_scram_sha512_route = bp.routes:insert {
        hosts = { "sync-sasl-scram-sha512-host.test" },
      }

      local sync_sasl_scram_delegation_token_route = bp.routes:insert {
        hosts = { "sync-sasl-scram-delegation-token-host.test" },
      }

      local sync_sasl_scram_sha_256_ssl_route = bp.routes:insert {
        hosts = { "sync-sasl-scram-sha256-ssl-host.test" },
      }

      local sync_sasl_scram_sha_512_ssl_route = bp.routes:insert {
        hosts = { "sync-sasl-scram-sha512-ssl-host.test" },
      }

      local sync_sasl_plain_ssl_route = bp.routes:insert {
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

     local custom_log_route = bp.routes:insert {
        hosts = { "custom-log-host.test" },
      }

      local cert = bp.certificates:insert({
        cert = ssl_helpers.cert,
        key = ssl_helpers.key
      })

      bp.plugins:insert {
        name = "kafka-log",
        route = { id = sync_mtls_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SSL_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
          security = {
            ssl = true,
            certificate_id = cert.id
          }
        }
      }
      bp.plugins:insert {
        name = "kafka-log",
        route = { id = sync_sasl_scram_sha256_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SASL_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
          authentication = {
            strategy = 'sasl',
            mechanism = 'SCRAM-SHA-256',
            user = 'client',
            password = 'client-password'
          },
          security = {
            ssl = false
          }
        }
      }
      bp.plugins:insert {
        name = "kafka-log",
        route = { id = sync_sasl_scram_sha512_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SASL_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
          authentication = {
            strategy = 'sasl',
            mechanism = 'SCRAM-SHA-512',
            user = 'client-sha512',
            password = 'client-password'
          },
          security = {
            ssl = false
          }
        }
      }
      bp.plugins:insert {
        name = "kafka-log",
        route = { id = sync_sasl_scram_delegation_token_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SASL_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
          authentication = {
            strategy = 'sasl',
            mechanism = 'SCRAM-SHA-256',
            tokenauth = true,
            user = 'uNiZIb-gQwGhQ08c013e5g',
            password = '4nxIhPuUQqNnVndPiGPbCj3fUBGKTUBenzauyBfv2us0nQ0DLbM79olPeLdwyUxi4tGt5mzwziTOXuZzrCMLEg==',
          },
          security = {
            ssl = false
          }
        }
      }

      bp.plugins:insert {
        name = "kafka-log",
        route = { id = sync_sasl_scram_sha_512_ssl_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SASL_SSL_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
          authentication = {
            strategy = 'sasl',
            mechanism = 'SCRAM-SHA-512',
            user = 'client-sha512',
            password = 'client-password'
          },
          security = {
            ssl = true,
            certificate_id = cert.id
          }
        }
      }

      bp.plugins:insert {
        name = "kafka-log",
        route = { id = sync_sasl_scram_sha_256_ssl_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SASL_SSL_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
          authentication = {
            strategy = 'sasl',
            mechanism = 'SCRAM-SHA-256',
            user = 'client',
            password = 'client-password'
          },
          security = {
            ssl = true,
            certificate_id = cert.id
          }
        }
      }

      bp.plugins:insert {
        name = "kafka-log",
        route = { id = sync_sasl_plain_ssl_route.id },
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
        name = "kafka-log",
        route = { id = sync_sasl_plain_route.id },
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
        name = "kafka-log",
        route = { id = sync_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = false,
          topic = 'sync_topic',
        }
      }

      bp.plugins:insert {
        name = "kafka-log",
        route = { id = async_timeout_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = true,
          producer_async_flush_timeout = FLUSH_TIMEOUT_MS,
          topic = 'async_timeout_topic',
        }
      }

      bp.plugins:insert {
        name = "kafka-log",
        route = { id = async_size_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = true,
          producer_async_flush_timeout = FLUSH_TIMEOUT_MS * 1000, -- never timeout
          producer_request_limits_messages_per_request = FLUSH_BATCH_SIZE,
          topic = 'async_size_topic',
        }
      }

      bp.plugins:insert {
        name = "kafka-log",
        route = { id = custom_log_route.id },
        config = {
          bootstrap_servers = BOOTSTRAP_SERVERS,
          producer_async = false,
          topic = 'custom_log_sync_topic',
          custom_fields_by_lua = {
            new_field = "return 123",
            route = "return nil", -- unset route field
          },
        }
      }

      assert(helpers.start_kong {
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,kafka-log",
      })
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
    lazy_setup(function()
      -- Execute before tests to setup topics in kafka
      local uri = "/post?key1=value1&key2=value2"
      local res = proxy_client:post(uri, {
        headers = {
          host = "sync-host.test",
          ["Content-Type"] = "application/json",
        },
        body = { foo = "bar" },
      })
      assert.res_status(200, res)
      local uri = "/post?key1=value1&key2=value2"
      local res = proxy_client:post(uri, {
        headers = {
          host = "async-timeout-host.test",
          ["Content-Type"] = "application/json",
        },
        body = { foo = "bar" },
      })
      assert.res_status(200, res)
      local uri = "/post?key1=value1&key2=value2"
      local res = proxy_client:post(uri, {
        headers = {
          host = "async-size-host.test",
          ["Content-Type"] = "application/json",
        },
        body = { foo = "bar" },
      })
      assert.res_status(200, res)
      local uri = "/post?key1=value1&key2=value2"
      local res = proxy_client:post(uri, {
        headers = {
          host = "custom-log-host.test",
          ["Content-Type"] = "application/json",
        },
        body = { foo = "bar" },
      })
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

      helpers.stop_kong()
    end)

    after_each(function()
      helpers.clean_logfile()
    end)

    describe("sync mode", function()
      it("sends data immediately after a request", function()
        local uri = "/post?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { foo = "bar" },
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")
        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")
      end)
    end)

    describe("sasl auth PLAIN", function()
      it("authenticates with sasl credentials [no ssl]", function()
        local uri = "/post?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-sasl-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { foo = "bar" },
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")
        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")
      end)

      it("authenticates with sasl credentials [ssl]", function()
        local uri = "/post?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-sasl-ssl-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { foo = "bar" },
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")
        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")
      end)
    end)

    describe("sasl auth SCRAM-SHA-256", function()
    it("[no ssl]", function()
        local uri = "/post?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-sasl-scram-sha256-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { scram = "no-ssl" },
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")
        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")
      end)

    it("[ssl]", function()
        local uri = "/post?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-sasl-scram-sha256-ssl-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { scram = "ssl" },
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")
        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")
      end)
    end)

    describe("sasl auth SCRAM-SHA-512", function()
    it("[no ssl]", function()
        local uri = "/post?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-sasl-scram-sha512-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { scram = "no-ssl" },
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")
        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")
      end)

    it("[ssl]", function()
        local uri = "/post?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-sasl-scram-sha512-ssl-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { scram = "ssl" },
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")
        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")
      end)
    end)

    describe("sasl auth delegation tokens", function()
      pending("[no ssl]", function()
        local uri = "/post?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-sasl-scram-delegation-token-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { scram = "delegation" },
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")
        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")
      end)
    end)

    describe("mtls", function()
      it("authenticates with certificates", function()
        local uri = "/post?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "sync-mtls-host.test",
            ["Content-Type"] = "application/json",
          },
          body = { foo = "bar" },
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")
        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")
      end)
    end)

    describe("async mode", function()
      it("sends batched data, after waiting long enough", function()
        local uri = "/post?key1=value1&key2=value2"
        local res = proxy_client:post(uri, {
          headers = {
            host = "async-timeout-host.test",
            ["Content-Type"] = "text/plain",
          },
          body = '{"foo":"bar"}',
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")
        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")
      end)
    end)

    describe("custom log values by lua", function()
      local base_uri
      before_each(function()
        local my_consumer = create_consumer("my_group", "my_consumer")
        base_uri = my_consumer.base_uri
        subscribe_topic(base_uri, "custom_log_sync_topic")
      end)
      after_each(function()
        if base_uri then
          delete_consumer(base_uri)
        end
      end)
      it("logs custom values", function()
        consume_all_records(base_uri)

        local uri = "/post?key1=value1&key2=custom-log"
        local res = proxy_client:post(uri, {
          headers = {
            host = "custom-log-host.test",
            ["Content-Type"] = "application/json",
          },
          body = '{"foo":"bar"}',
        })
        assert.res_status(200, res)

        assert
          .with_timeout(30)
          .ignore_exceptions(false)
          .eventually(function()
            assert.logfile().has.line("start to send a message on topic", true, 10)
          end)
          .has_no_error("kafka log timer gets run")

        assert.logfile().has_not.line("failed to find or load certificate")
        assert.logfile().has_not.line("could not create Kafka Producer from given configuration")
        assert.logfile().has_not.line("could not send message to topic")
        assert.logfile().has_not.line("error sending message to Kafka topic")

        local records = wait_for_records(base_uri)
        assert.same(1, #records)
        local message = cjson.decode(ngx.decode_base64(records[1].value))
        assert.same("/post?key1=value1&key2=custom-log", message.request.uri)
        assert.same(123, message.new_field)
        assert.same(nil, message.route)

      end)
    end)
  end)
end
