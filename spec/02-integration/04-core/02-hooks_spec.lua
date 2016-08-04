local helpers = require "spec.helpers"
local cjson = require "cjson"
local cache = require "kong.tools.database_cache"
local pl_tablex = require "pl.tablex"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_stringx = require "pl.stringx"

describe("Core Hooks", function()
  local client, api_client
  local consumer, api1, api2, basic_auth2, api3, rate_limiting_consumer

  before_each(function()
    helpers.start_kong()
    client = helpers.proxy_client()
    api_client = helpers.admin_client()

    consumer = assert(helpers.dao.consumers:insert {
      username = "consumer1"
    })
    assert(helpers.dao.basicauth_credentials:insert {
      username = "user123",
      password = "pass123",
      consumer_id = consumer.id
    })

    api1 = assert(helpers.dao.apis:insert {
      request_host = "hooks1.com",
      upstream_url = "http://mockbin.com"
    })

    api2 = assert(helpers.dao.apis:insert {
      request_host = "hooks-consumer.com",
      upstream_url = "http://mockbin.com"
    })
    basic_auth2 = assert(helpers.dao.plugins:insert {
      name = "basic-auth",
      api_id = api2.id,
      config = {}
    })

    api3 = assert(helpers.dao.apis:insert {
      request_host = "hooks-plugins.com",
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

  describe("API entity invalidation", function()
    it("should invalidate ALL_APIS_BY_DICT when adding a new API", function()
      -- Making a request to populate ALL_APIS_BY_DICT
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "hooks1.com"
        }
      })
      assert.res_status(200, res)

      -- Make sure the cache is populated
      local res = assert(api_client:send {
        method = "GET",
        path = "/cache/"..cache.all_apis_by_dict_key()
      })
      assert.res_status(200, res)

      -- Adding a new API
      local res = assert(api_client:send {
        method = "POST",
        path = "/apis/",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = cjson.encode({
          request_host = "dynamic-hooks.com",
          upstream_url = "http://mockbin.org"
        })
      })
      assert.res_status(201, res)

      -- Wait for consumer be invalidated
      helpers.wait_until(function()
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.all_apis_by_dict_key(),
          headers = {}
        })
        res:read_body()
        return res.status == 404
      end, 3)

      -- Consuming the API again
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "hooks1.com"
        }
      })
      assert.res_status(200, res)

      -- Make sure the cache is populated
      local res = assert(api_client:send {
        method = "GET",
        path = "/cache/"..cache.all_apis_by_dict_key()
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.is_table(body.by_dns["hooks1.com"])
      assert.is_table(body.by_dns["dynamic-hooks.com"])
    end)

    it("should invalidate ALL_APIS_BY_DICT when updating an API", function()
      -- Making a request to populate ALL_APIS_BY_DICT
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "hooks1.com"
        }
      })
      assert.res_status(200, res)

      -- Make sure the cache is populated
      local res = assert(api_client:send {
        method = "GET",
        path = "/cache/"..cache.all_apis_by_dict_key()
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("http://mockbin.com", body.by_dns["hooks1.com"].upstream_url)

      -- Update API
      local res = assert(api_client:send {
        method = "PATCH",
        path = "/apis/"..api1.id,
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = cjson.encode({
          upstream_url = "http://mockbin.org"
        })
      })
      assert.res_status(200, res)

      -- Wait for consumer be invalidated
      helpers.wait_until(function()
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.all_apis_by_dict_key(),
          headers = {}
        })
        res:read_body()
        return res.status == 404
      end, 3)

      -- Consuming the API again
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "hooks1.com"
        }
      })
      assert.res_status(200, res)

      -- Make sure the cache is populated with updated value
      local res = assert(api_client:send {
        method = "GET",
        path = "/cache/"..cache.all_apis_by_dict_key(),
        headers = {}
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("http://mockbin.org", body.by_dns["hooks1.com"].upstream_url)
      assert.equal(3, pl_tablex.size(body.by_dns))
    end)

    it("should invalidate ALL_APIS_BY_DICT when deleting an API", function()
      -- Making a request to populate ALL_APIS_BY_DICT
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "hooks1.com"
        }
      })
      assert.res_status(200, res)

      -- Make sure the cache is populated
      local res = assert(api_client:send {
        method = "GET",
        path = "/cache/"..cache.all_apis_by_dict_key()
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal("http://mockbin.com", body.by_dns["hooks1.com"].upstream_url)

      -- Deleting the API
      local res = assert(api_client:send {
        method = "DELETE",
        path = "/apis/"..api1.id
      })
      assert.res_status(204, res)

      -- Wait for consumer be invalidated
      helpers.wait_until(function()
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.all_apis_by_dict_key(),
          headers = {}
        })
        res:read_body()
        return res.status == 404
      end, 3)

      -- Consuming the API again
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "hooks1.com"
        }
      })
      assert.res_status(404, res)

      -- Make sure the cache is populated with zero APIs
      local res = assert(api_client:send {
        method = "GET",
        path = "/cache/"..cache.all_apis_by_dict_key()
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.equal(2, pl_tablex.size(body.by_dns))
    end)
  end)

  describe("Serf events", function()
    local PID_FILE = "/tmp/serf_test.pid"
    local LOG_FILE = "/tmp/serf_test.log"

    local function kill(pid_file, args)
      local cmd = string.format([[kill %s `cat %s` >/dev/null 2>&1]], args or "-0", pid_file)
      return os.execute(cmd)
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
      os.execute(string.format("kill `cat %s` >/dev/null 2>&1", PID_FILE))
    end

    it("should syncronize nodes on members events", function()
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
