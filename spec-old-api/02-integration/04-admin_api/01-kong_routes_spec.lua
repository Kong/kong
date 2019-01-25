local helpers = require "spec.helpers"
local cjson = require "cjson"

local dao_helpers = require "spec.02-integration.03-dao.helpers"

describe("Admin API - Kong routes", function()
  describe("/", function()
    local meta = require "kong.meta"
    local client

    lazy_setup(function()
      helpers.get_db_utils()
      assert(helpers.start_kong {
        pg_password = "hide_me"
      })
      client = helpers.admin_client(10000)
    end)

    lazy_teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)

    it("returns Kong's version number and tagline", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(meta._VERSION, json.version)
      assert.equal("Welcome to kong", json.tagline)
    end)
    it("response has the correct Server header", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      assert.res_status(200, res)
      assert.equal(meta._SERVER_TOKENS, res.headers.server)
      assert.is_nil(res.headers.via) -- Via is only set for proxied requests
    end)
    it("returns 405 on invalid method", function()
      local methods = {"POST", "PUT", "DELETE", "PATCH", "GEEEET"}
      for i = 1, #methods do
        local res = assert(client:send {
          method = methods[i],
          path = "/",
          body = {}, -- tmp: body to allow POST/PUT to work
          headers = {["Content-Type"] = "application/json"}
        })
        local body = assert.response(res).has.status(405)
        local json = cjson.decode(body)
        assert.same({ message = "Method not allowed" }, json)
      end
    end)
    it("exposes the node's configuration", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.configuration)
    end)
    it("enabled_in_cluster property is an array", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      assert.matches('"enabled_in_cluster":[', body, nil, true)
    end)
    it("obfuscates sensitive settings from the configuration", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_string(json.configuration.pg_password)
      assert.not_equal("hide_me", json.configuration.pg_password)
    end)
    it("returns PRNG seeds", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
      })
      local body = assert.response(res).has.status(200)
      local json = cjson.decode(body)
      assert.is_table(json.prng_seeds)
      for k, v in pairs(json.prng_seeds) do
        assert.matches("pid: %d+", k)
        assert.matches("%d+", k)
      end
    end)
  end)

  dao_helpers.for_each_dao(function(kong_conf)
    describe("/status with DB: #" .. kong_conf.database, function()
      local client

      lazy_setup(function()
        helpers.get_db_utils(kong_conf.database)

        assert(helpers.start_kong {
          database = kong_conf.database,
        })
        client = helpers.admin_client(10000)
      end)

      lazy_teardown(function()
        if client then client:close() end
        helpers.stop_kong()
      end)

      it("returns status info", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.database)
        assert.is_table(json.server)

        assert.is_boolean(json.database.reachable)

        assert.is_number(json.server.connections_accepted)
        assert.is_number(json.server.connections_active)
        assert.is_number(json.server.connections_handled)
        assert.is_number(json.server.connections_reading)
        assert.is_number(json.server.connections_writing)
        assert.is_number(json.server.connections_waiting)
        assert.is_number(json.server.total_requests)
      end)

      it("database.reachable is `true` when DB connection is healthy", function()
        -- In this test, we know our DB is reachable because it must be
        -- so in our test suite. Ideally, a test when the DB isn't reachable
        -- should be provided (start Kong, kill DB, request `/status`),
        -- but this isn't currently possible in our test suite.
        -- Additionally, let's emphasize that we only test DB connection, not
        -- the health of said DB itself.

        local res = assert(client:send {
          method = "GET",
          path = "/status"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.is_true(json.database.reachable)
      end)
    end)
  end)
end)
