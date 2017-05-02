local helpers = require "spec.helpers"
local cjson = require "cjson"
local cache = require "kong.tools.database_cache"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_stringx = require "pl.stringx"

-- cache entry inserted as a sentinel whenever a db lookup returns nothing
local DB_MISS_SENTINEL = { null = true }

describe("Core Hooks", function()
  describe("Global", function()
    describe("Plugin entity invalidation on API", function()
      local client, api_client, db_miss_api
      local plugin

      before_each(function()
        assert(helpers.dao.apis:insert {
          name = "hooks1",
          hosts = { "hooks1.com" },
          upstream_url = "http://mockbin.com"
        })

        plugin = assert(helpers.dao.plugins:insert {
          name = "rate-limiting",
          config = { minute = 10 }
        })

        assert(helpers.dao.apis:insert {
          name = "hooks2",
          hosts = { "hooks2.com" },
          upstream_url = "http://mockbin.com"
        })

        assert(helpers.dao.apis:insert {
          name = "db-miss",
          hosts = { "db-miss.org" },
          upstream_url = "http://mockbin.com"
        })

        db_miss_api = assert(helpers.dao.apis:insert {
          name = "db-miss-you-too",
          hosts = { "db-miss-you-too.org" },
          upstream_url = "http://mockbin.com"
        })
        assert(helpers.dao.plugins:insert {
          name = "correlation-id",
          api_id = db_miss_api.id
        })


        helpers.start_kong()
        client = helpers.proxy_client()
        api_client = helpers.admin_client()
      end)
      after_each(function()
        if client and api_client then
          client:close()
          api_client:close()
        end
        helpers.stop_kong()
      end)

      it("inserts sentinel values for db-miss", function()
        -- test case specific for https://github.com/Mashape/kong/pull/1841
        -- make a request, to populate cache with sentinel values
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "db-miss.org"
          }
        })
        assert.response(res).has.status(200)

        -- check sentinel value for global plugin; pluginname, nil, nil
        local cache_path = "/cache/"..cache.plugin_key("correlation-id", nil, nil)
        local res = assert(api_client:send {
          method = "GET",
          path = cache_path
        })
        assert.response(res).has.status(200)
        assert.same(DB_MISS_SENTINEL, assert.response(res).has.jsonbody())
      end)

      it("should invalidate a global plugin when adding", function()
        -- on a db-miss a sentinel value is inserted in the cache to prevent
        -- too many db lookups. This sentinel value should be invalidated when
        -- adding a plugin.

        -- Making a request to populate the cache
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks2.com"
          }
        })
        assert.response(res).has.status(200)

        -- Make sure the cache is not populated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.plugin_key("basic-auth", nil, nil)
        })
        local entry = cjson.decode(assert.res_status(200, res))
        assert.same(DB_MISS_SENTINEL, entry)  -- db-miss sentinel value

        -- Add plugin
        local res = assert(api_client:send {
          method = "POST",
          path = "/plugins/",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = cjson.encode({
            name = "basic-auth"
          })
        })
        assert.response(res).has.status(201)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.plugin_key("basic-auth", nil, nil)
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Making a request: replacing the db-miss sentinel value in cache
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks2.com"
          }
        })
        assert.response(res).has.status(401) -- in effect plugin, so failure

        -- Make sure the cache is populated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.plugin_key("basic-auth", nil, nil)
        })
        local entry = cjson.decode(assert.res_status(200, res))
        assert.is_true(entry.enabled)
        assert.is.same("basic-auth", entry.name)
      end)

      it("should invalidate a global plugin when deleting", function()
        -- Making a request to populate the cache
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks1.com"
          }
        })
        assert.res_status(200, res)
        assert.is_string(res.headers["X-RateLimit-Limit-minute"])

        -- Make sure the cache is populated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.plugin_key("rate-limiting", nil, nil)
        })
        assert.res_status(200, res)

        -- Delete plugin
        local res = assert(api_client:send {
          method = "DELETE",
          path = "/plugins/"..plugin.id
        })
        assert.res_status(204, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.plugin_key("rate-limiting", nil, nil)
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Consuming the API again without any authorization
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks1.com"
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["X-RateLimit-Limit-minute"])
      end)
    end)

    describe("Global Plugin entity invalidation on Consumer", function()
      local client, api_client
      local plugin, consumer

      setup(function()
         helpers.dao:truncate_tables()
      end)
      before_each(function()
        assert(helpers.dao.apis:insert {
          name = "hook1",
          hosts = { "hooks1.com" },
          upstream_url = "http://mockbin.com"
        })

        assert(helpers.dao.plugins:insert {
          name = "key-auth",
          config = {}
        })

        consumer = assert(helpers.dao.consumers:insert {
          username = "test"
        })
        assert(helpers.dao.keyauth_credentials:insert {
          key = "kong",
          consumer_id = consumer.id
        })

        plugin = assert(helpers.dao.plugins:insert {
          name = "rate-limiting",
          consumer_id = consumer.id,
          config = { minute = 10 }
        })

        helpers.start_kong()
        client = helpers.proxy_client()
        api_client = helpers.admin_client()
      end)
      after_each(function()
        if client and api_client then
          client:close()
          api_client:close()
        end
        helpers.stop_kong()
      end)

      it("should invalidate a global plugin when deleting", function()
        -- Making a request to populate the cache
        local res = assert(client:send {
          method = "GET",
          path = "/status/200?apikey=kong",
          headers = {
            ["Host"] = "hooks1.com"
          }
        })
        assert.res_status(200, res)
        assert.is_string(res.headers["X-RateLimit-Limit-minute"])

        -- Make sure the cache is populated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.plugin_key("rate-limiting", nil, consumer.id)
        })
        assert.res_status(200, res)

        -- Delete plugin
        local res = assert(api_client:send {
          method = "DELETE",
          path = "/plugins/"..plugin.id
        })
        assert.res_status(204, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.plugin_key("rate-limiting", nil, consumer.id)
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Consuming the API again without any authorization
        local res = assert(client:send {
          method = "GET",
          path = "/status/200?apikey=kong",
          headers = {
            ["Host"] = "hooks1.com"
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["X-RateLimit-Limit-minute"])

         -- Delete consumer
        local res = assert(api_client:send {
          method = "DELETE",
          path = "/consumers/"..consumer.id
        })
        assert.res_status(204, res)

        local res = assert(client:send {
          method = "GET",
          path = "/status/200?apikey=kong",
          headers = {
            ["Host"] = "hooks1.com"
          }
        })
        assert.res_status(200, res)
        assert.is_nil(res.headers["X-RateLimit-Limit-minute"])

        local res = assert(api_client:send {
          method = "GET",
          path = "/plugins/"..plugin.id,
        })
        assert.res_status(404, res)
      end)
    end)
  end)

  describe("Other", function()
    local client, api_client
    local consumer, api2, basic_auth2, api3, rate_limiting_consumer

    before_each(function()
      consumer = assert(helpers.dao.consumers:insert {
        username = "consumer1"
      })
      assert(helpers.dao.basicauth_credentials:insert {
        username = "user123",
        password = "pass123",
        consumer_id = consumer.id
      })

      assert(helpers.dao.apis:insert {
        name = "hook1",
        hosts = { "hooks1.com" },
        upstream_url = "http://mockbin.com"
      })

      api2 = assert(helpers.dao.apis:insert {
        name = "hook2",
        hosts = { "hooks-consumer.com" },
        upstream_url = "http://mockbin.com"
      })
      basic_auth2 = assert(helpers.dao.plugins:insert {
        name = "basic-auth",
        api_id = api2.id,
        config = {}
      })

      api3 = assert(helpers.dao.apis:insert {
        name = "hook3",
        hosts = { "hooks-plugins.com" },
        upstream_url = "http://mockbin.com"
      })
      assert(helpers.dao.plugins:insert {
        name = "basic-auth",
        api_id = api3.id,
        config = {}
      })
      assert(helpers.dao.plugins:insert {
        name = "rate-limiting",
        api_id = api3.id,
        config = {
          minute = 10
        }
      })
      rate_limiting_consumer = assert(helpers.dao.plugins:insert {
        name = "rate-limiting",
        api_id = api3.id,
        consumer_id = consumer.id,
        config = {
          minute = 3
        }
      })

      helpers.start_kong()
      client = helpers.proxy_client()
      api_client = helpers.admin_client()
    end)
    after_each(function()
      if client and api_client then
        client:close()
        api_client:close()
      end
      helpers.stop_kong()
    end)

    describe("Plugin entity invalidation", function()
      it("should invalidate a plugin when deleting", function()
        -- Making a request to populate the cache
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-consumer.com",
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzMTIz"
          }
        })
        assert.res_status(200, res)

        -- Make sure the cache is populated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.plugin_key("basic-auth", api2.id, nil)
        })
        assert.res_status(200, res)

        -- Delete plugin
        local res = assert(api_client:send {
          method = "DELETE",
          path = "/apis/"..api2.id.."/plugins/"..basic_auth2.id
        })
        assert.res_status(204, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.plugin_key("basic-auth", api2.id, nil)
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Consuming the API again without any authorization
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-consumer.com"
          }
        })
        assert.res_status(200, res)
      end)

      it("should invalidate a plugin when updating", function()
        -- Consuming the API without any authorization
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-consumer.com"
          }
        })
        assert.res_status(401, res)

        -- Making a request to populate the cache
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-consumer.com",
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzMTIz"
          }
        })
        assert.res_status(200, res)

        -- Make sure the cache is populated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.plugin_key("basic-auth", api2.id, nil)
        })
        assert.res_status(200, res)

        -- Update plugin
        local res = assert(api_client:send {
          method = "PATCH",
          path = "/apis/"..api2.id.."/plugins/"..basic_auth2.id,
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = cjson.encode({
            enabled = false
          })
        })
        assert.res_status(200, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.plugin_key("basic-auth", api2.id, nil)
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Consuming the API again without any authorization
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-consumer.com"
          }
        })
        assert.res_status(200, res)
      end)

      it("should invalidate a consumer-specific plugin when deleting", function()
        -- Making a request to populate the cache
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-plugins.com",
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzMTIz"
          }
        })
        assert.res_status(200, res)
        assert.equal(3, tonumber(res.headers["x-ratelimit-limit-minute"]))

        -- Make sure the cache is populated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.plugin_key("rate-limiting", api3.id, consumer.id)
        })
        assert.res_status(200, res)

        -- Delete plugin
        local res = assert(api_client:send {
          method = "DELETE",
          path = "/apis/"..api3.id.."/plugins/"..rate_limiting_consumer.id
        })
        assert.res_status(204, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.plugin_key("rate-limiting", api3.id, consumer.id)
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Consuming the API again
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-plugins.com",
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzMTIz"
          }
        })
        assert.res_status(200, res)
        assert.equal(10, tonumber(res.headers["x-ratelimit-limit-minute"]))
      end)

      it("should invalidate a consumer-specific plugin when updating", function()
        -- Making a request to populate the cache
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-plugins.com",
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzMTIz"
          }
        })
        assert.res_status(200, res)
        assert.equal(3, tonumber(res.headers["x-ratelimit-limit-minute"]))

        -- Make sure the cache is populated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.plugin_key("rate-limiting", api3.id, consumer.id)
        })
        assert.res_status(200, res)

        -- Update plugin
        local res = assert(api_client:send {
          method = "PATCH",
          path = "/apis/"..api3.id.."/plugins/"..rate_limiting_consumer.id,
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = cjson.encode({
            enabled = false
          })
        })
        assert.res_status(200, res)

        -- Wait for cache to be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.plugin_key("rate-limiting", api3.id, consumer.id)
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Consuming the API again
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-plugins.com",
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzMTIz"
          }
        })
        assert.res_status(200, res)
        assert.equal(10, tonumber(res.headers["x-ratelimit-limit-minute"]))
      end)
    end)

    describe("Consumer entity invalidation", function()
      it("should invalidate a consumer when deleting", function()
        -- Making a request to populate the cache
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-consumer.com",
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzMTIz"
          }
        })
        assert.res_status(200, res)

        -- Make sure the cache is populated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.consumer_key(consumer.id)
        })
        assert.res_status(200, res)

        -- Delete consumer
        local res = assert(api_client:send {
          method = "DELETE",
          path = "/consumers/"..consumer.id
        })
        assert.res_status(204, res)

        -- Wait for consumer be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.consumer_key(consumer.id)
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Wait for Basic Auth credential to be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.basicauth_credential_key("user123")
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Consuming the API again
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-consumer.com",
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzMTIz"
          }
        })
        assert.res_status(403, res)
      end)

      it("should invalidate a consumer when updating", function()
        -- Making a request to populate the cache
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-consumer.com",
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzMTIz"
          }
        })
        assert.res_status(200, res)

        -- Make sure the cache is populated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.consumer_key(consumer.id)
        })
        assert.res_status(200, res)

        -- Update consumer
        local res = assert(api_client:send {
          method = "PATCH",
          path = "/consumers/"..consumer.id,
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = cjson.encode({
            username = "updated_consumer"
          })
        })
        assert.res_status(200, res)

        -- Wait for consumer be invalidated
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cache/"..cache.consumer_key(consumer.id)
          })
          res:read_body()
          return res.status == 404
        end, 3)

        -- Consuming the API again
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "hooks-consumer.com",
            ["Authorization"] = "Basic dXNlcjEyMzpwYXNzMTIz"
          }
        })
        assert.res_status(200, res)

        -- Making sure the cache is updated
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.consumer_key(consumer.id)
        })
        local body = assert.res_status(200, res)
        assert.equal("updated_consumer", cjson.decode(body).username)
      end)
    end)

    describe("Serf events", function()
      local PID_FILE = "/tmp/serf_test.pid"
      local LOG_FILE = "/tmp/serf_test.log"

      local function kill(pid_file, args)
        local cmd = string.format([[kill %s `cat %s` >/dev/null 2>&1]], args or "-0", pid_file)
        local ok, code = pl_utils.execute(cmd)
        if ok then
          return code
        end
      end

      local function is_running(pid_path)
        if not pl_path.exists(pid_path) then return nil end
        local code = kill(pid_path, "-0")
        return code == 0
      end

      local function start_serf()
        local args = {
          ["-node"] = "test_node",
          ["-bind"] = "127.0.0.1:10000",
          ["-profile"] = "lan",
          ["-rpc-addr"] = "127.0.0.1:10001"
        }
        setmetatable(args, require "kong.tools.printable")

        local cmd = string.format("nohup %s agent %s > %s 2>&1 & echo $! > %s",
                    helpers.test_conf.serf_path,
                    tostring(args),
                    LOG_FILE, PID_FILE)

        -- start Serf agent
        local ok = pl_utils.execute(cmd)
        if not ok then return error("Cannot start Serf") end

        -- ensure started (just an improved version of previous Serf service)
        local start_timeout = 5
        local tstart = ngx.time()
        local texp, started = tstart + start_timeout

        repeat
          ngx.sleep(0.2)
          started = is_running(PID_FILE)
        until started or ngx.time() >= texp

        if not started then
          -- time to get latest error log from serf.log
          local logs = pl_file.read(LOG_FILE)
          local tlogs = pl_stringx.split(logs, "\n")
          local err = string.gsub(tlogs[#tlogs-1], "==> ", "")
          err = pl_stringx.strip(err)
          error("could not start Serf:\n  "..err)
        end

        if not ok then error("Error starting serf") end
      end

      local function stop_serf()
        pl_utils.execute(string.format("kill `cat %s` >/dev/null 2>&1", PID_FILE))
      end

      it("should synchronize nodes on members events", function()
        start_serf()

        -- Tell Kong to join the new Serf
        local res = assert(api_client:send {
          method = "POST",
          path = "/cluster/",
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = cjson.encode({address = "127.0.0.1:10000"})
        })
        assert.res_status(200, res)

        -- Wait until the node joins
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cluster/"
          })
          local body = cjson.decode(assert.res_status(200, res))
          if #body.data == 2 then
            local found
            for _, v in ipairs(body.data) do
              if v.address == "127.0.0.1:10000" then
                found = true
                assert.equal("test_node", v.name)
                assert.equal("alive", v.status)
              else
                assert.is_string(v.name)
                assert.equal("alive", v.status)
              end
            end
            return found
          end
        end, 5)

        -- Killing serf
        stop_serf()

        -- Wait until the node appears as failed
        helpers.wait_until(function()
          local res = assert(api_client:send {
            method = "GET",
            path = "/cluster/"
          })
          local body = cjson.decode(assert.res_status(200, res))
          local found
          if #body.data == 2 then
            for _, v in ipairs(body.data) do
              if v.address == "127.0.0.1:10000" then
                if v.name == "test_node" and v.status == "failed" then
                  found = true
                end
              else
                assert.is_string(v.name)
                assert.equal("alive", v.status)
              end
            end
          end
          ngx.sleep(1)
          return found
        end, 60)

        finally(function()
          stop_serf()
        end)
      end)
    end)
  end)
end)
