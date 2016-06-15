local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"
local cache = require "kong.tools.database_cache"

local TIMEOUT = 10

describe("Core Hooks", function()
  local client, api_client
  local api2, basic_auth2
  setup(function()
    helpers.dao:truncate_tables()
    helpers.execute "pkill nginx; pkill serf; pkill dnsmasq"
    assert(helpers.prepare_prefix())

    local consumer = assert(helpers.dao.consumers:insert {
      username = "consumer1"
    })
    assert(helpers.dao.basicauth_credentials:insert {
      username = "user123",
      password = "pass123",
      consumer_id = consumer.id
    })

    assert(helpers.dao.apis:insert {
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

    local api3 = assert(helpers.dao.apis:insert {
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
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api3.id,
      consumer_id = consumer.id,
      config = {
        minute = 10
      }
    })

    assert(helpers.start_kong())
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
    api_client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)
  teardown(function()
    if client then
      client:close()
    end
    if api_client then
      api_client:close()
    end
    helpers.stop_kong()
    --helpers.clean_prefix()
  end)

  local function timeout_while(timeout, fn)
    local start = os.time()
    while(os.time() < (start + timeout)) do
      if fn() then return end
    end
    error("Timeout")
  end

  describe("Plugin entity invalidation", function()
    it("#only should invalidate a plugin when deleting", function()
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
        path = "/cache/"..cache.plugin_key("basic-auth", api2.id, nil),
        headers = {}
      })
      assert.res_status(200, res)
      
      -- Delete plugin
      local res = assert(api_client:send {
        method = "DELETE",
        path = "/apis/"..api2.id.."/plugins/"..basic_auth2.id,
        headers = {}
      })
      assert.res_status(204, res)

      -- Wait for cache to be invalidated
      timeout_while(TIMEOUT, function()
        os.execute("sleep 0.2") -- Apparently api_client cannot be reused immediately
        local res = assert(api_client:send {
          method = "GET",
          path = "/cache/"..cache.plugin_key("basic-auth", api2.id, nil),
          headers = {}
        })
        if res.status ~= 200 then
          assert.res_status(404, res)
          return true
        end
      end)
    end)

    it("should invalidate a consumer-specific plugin when deleting", function()
      error("TODO")
    end)

    it("should invalidate a consumer-specific plugin when updating", function()
      error("TODO")
    end)

    it("should invalidate a plugin when updating", function()
      error("TODO")
    end)
  end)

  describe("Consumer entity invalidation", function()
    it("should invalidate a consumer when deleting", function()
      error("TODO")
    end)

    it("should invalidate a consumer when updating", function()
      error("TODO")
    end)
  end)

  describe("API entity invalidation", function()
    it("should invalidate ALL_APIS_BY_DICT when adding a new API", function()
      error("TODO")
    end)

    it("should invalidate ALL_APIS_BY_DICT when updating an API", function()
      error("TODO")
    end)

    it("should invalidate ALL_APIS_BY_DICT when deleting an API", function()
      error("TODO")
    end)
  end)

  describe("Serf events", function()
    it("should syncronize nodes on members events", function()
      error("TODO")
    end)
  end)
end)
