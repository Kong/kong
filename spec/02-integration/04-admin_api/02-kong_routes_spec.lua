local helpers = require "spec.helpers"
local cjson = require "cjson"

local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"

local strategies = {}
for _, strategy in helpers.each_strategy() do
  table.insert(strategies, strategy)
end
table.insert(strategies, "off")
for _, strategy in pairs(strategies) do
describe("Admin API - Kong routes with strategy #" .. strategy, function()
  local meta = require "kong.meta"
  local client

  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    assert(helpers.start_kong {
      plugins = "bundled,reports-api",
      pg_password = "hide_me"
    })
    client = helpers.admin_client(10000)
  end)

  lazy_teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("/", function()
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
    it("returns a UUID as the node_id", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.matches(UUID_PATTERN, json.node_id)
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
      assert.matches('"enabled_in_cluster":[]', body, nil, true)
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
      for k in pairs(json.prng_seeds) do
        assert.matches("pid: %d+", k)
        assert.matches("%d+", k)
      end
    end)
  end)


  describe("/endpoints", function()
    it("only returns base, plugin, and custom-plugin endpoints", function()
      local res = assert(client:send {
        method = "GET",
        path = "/endpoints"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      local function find(endpoint)
        for _, ep in ipairs(json.data) do
          if ep == endpoint then
            return true
          end
        end
        return nil, ("endpoint '%s' not found in list of endpoints from " ..
                     "`/endpoints`"):format(endpoint)
      end

      assert(find("/plugins"))                             -- Kong base endpoint
      assert(find("/basic-auths/{basicauth_credentials}")) -- Core plugin endpoint
      assert(find("/reports/send-ping"))                   -- Custom plugin "reports-api"
    end)
  end)


  describe("/status", function()
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

    describe("memory stats", function()
      it("returns lua_shared_dicts memory stats", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local lua_shared_dicts = json.memory.lua_shared_dicts

        assert.matches("%d+%.%d+ MiB", lua_shared_dicts.kong.capacity)
        assert.matches("%d+%.%d+ MiB", lua_shared_dicts.kong.allocated_slabs)
        assert.matches("%d+%.%d+ MiB", lua_shared_dicts.kong_db_cache.capacity)
        assert.matches("%d+%.%d+ MiB", lua_shared_dicts.kong_db_cache.allocated_slabs)
      end)

      it("returns workers Lua VM allocated memory", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local workers_lua_vms = json.memory.workers_lua_vms

        for _, worker in ipairs(workers_lua_vms) do
          assert.matches("%d+%.%d+ MiB", worker.http_allocated_gc)
          assert.matches("%d+", worker.pid)
          assert.is_number(worker.pid)
        end
      end)

      it("returns workers in ascending PID values", function()
        do
          -- restart with 2 workers
          if client then
            client:close()
          end

          helpers.stop_kong()

          assert(helpers.start_kong {
            nginx_worker_processes = 2,
          })

          client = helpers.admin_client(10000)
        end

        finally(function()
          -- restart with default number of workers
          if client then
            client:close()
          end

          helpers.stop_kong()
          assert(helpers.start_kong())
          client = helpers.admin_client(10000)
        end)

        local res = assert(client:send {
          method = "GET",
          path = "/status",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local workers_lua_vms = json.memory.workers_lua_vms

        if #workers_lua_vms > 1 then
          for i = 1, #workers_lua_vms do
            if workers_lua_vms[i + 1] then
              assert.gt(workers_lua_vms[i].pid, workers_lua_vms[i + 1].pid)
            end
          end
        end
      end)

      it("accepts a 'unit' querystring argument", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status?unit=k",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local lua_shared_dicts = json.memory.lua_shared_dicts
        local workers_lua_vms = json.memory.workers_lua_vms

        assert.matches("%d+%.%d+ KiB", lua_shared_dicts.kong.capacity)
        assert.matches("%d+%.%d+ KiB", workers_lua_vms[1].http_allocated_gc)
      end)

      it("when unit is bytes, returned properties are numbers", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status?unit=b",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local lua_shared_dicts = json.memory.lua_shared_dicts
        local workers_lua_vms = json.memory.workers_lua_vms

        assert.matches("%d+", lua_shared_dicts.kong.capacity)
        assert.is_number(lua_shared_dicts.kong.capacity)

        assert.matches("%d+", lua_shared_dicts.kong.allocated_slabs)
        assert.is_number(lua_shared_dicts.kong.allocated_slabs)

        assert.matches("%d+", workers_lua_vms[1].http_allocated_gc)
        assert.is_number(workers_lua_vms[1].http_allocated_gc)
      end)

      it("accepts a 'scale' querystring argument", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status?scale=3",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        local lua_shared_dicts = json.memory.lua_shared_dicts
        local workers_lua_vms = json.memory.workers_lua_vms

        assert.matches("%d+%.%d%d%d MiB", lua_shared_dicts.kong.capacity)
        assert.matches("%d+%.%d%d%d MiB", workers_lua_vms[1].http_allocated_gc)
      end)

      it("returns HTTP 400 on invalid 'unit' querystring parameter", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status?unit=V",
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.equal("invalid unit 'V' (expected 'k/K', 'm/M', or 'g/G')",
                     json.message)
      end)
    end)
  end)

  describe("/schemas/:entity", function()
    it("returns the schema of all DB entities", function()
      for _, dao in pairs(helpers.db.daos) do
        local res = assert(client:send {
          method = "GET",
          path = "/schemas/" .. dao.schema.name,
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.fields)
      end
    end)
    it("returns 404 on a missing entity", function()
      local res = assert(client:send {
        method = "GET",
        path = "/schemas/not-present",
      })
      local body = assert.res_status(404, res)
      local json = cjson.decode(body)
      assert.same({ message = "No entity named 'not-present'" }, json)
    end)
    it("does not return schema of a foreign key", function()
      local res = assert(client:send {
        method = "GET",
        path = "/schemas/routes",
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      for _, field in pairs(json.fields) do
        if next(field) == "service" then
          local fdata = field["service"]
          assert.is_nil(fdata.schema)
        end
      end
    end)
  end)

  describe("/schemas/:entity", function()
    it("returns schema of all plugins", function()
      for plugin, _ in pairs(helpers.test_conf.loaded_plugins) do
        local res = assert(client:send {
          method = "GET",
          path = "/schemas/plugins/" .. plugin,
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.fields)
      end
    end)
    it("returns 404 on a non-existent plugin", function()
      local res = assert(client:send {
        method = "GET",
        path = "/schemas/plugins/not-present",
      })
      local body = assert.res_status(404, res)
      local json = cjson.decode(body)
      assert.same({ message = "No plugin named 'not-present'" }, json)
    end)
  end)


  describe("/schemas/:db_entity_name/validate", function()
    it("returns 200 on a valid schema", function()
      local res = assert(client:post("/schemas/services/validate", {
        body = { host = "example.com" },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("schema validation successful", json.message)
    end)
    it("returns 200 on a valid plugin schema", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          config = {
            key_names = { "foo", "bar" },
            hide_credentials = true,
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("schema validation successful", json.message)
    end)
    it("returns 400 on an invalid plugin subschema", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "key-auth",
          config = {
            keys = "foo",
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.equal("schema violation", json.name)
    end)
  end)
end)
end
