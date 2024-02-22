local helpers = require "spec.helpers"
local cjson = require "cjson"
local constants = require "kong.constants"

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
      database = strategy,
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
    it("returns headers with HEAD method", function()
      local res1 = assert(client:send {
        method = "GET",
        path = "/"
      })

      local body = assert.res_status(200, res1)
      assert.not_equal("", body)

      local res2 = assert(client:send {
        method = "HEAD",
        path = "/"
      })
      local body = assert.res_status(200, res2)
      assert.equal("", body)

      res1.headers["Date"] = nil
      res2.headers["Date"] = nil
      res1.headers["X-Kong-Admin-Latency"] = nil
      res2.headers["X-Kong-Admin-Latency"] = nil

      assert.same(res1.headers, res2.headers)
    end)

    it("returns allow and CORS headers with OPTIONS method", function()
      local res = assert(client:send {
        method = "OPTIONS",
        path = "/"
      })

      local body = assert.res_status(204, res)
      assert.equal("", body)
      assert.equal("GET, HEAD, OPTIONS", res.headers["Allow"])
      assert.equal("GET, HEAD, OPTIONS", res.headers["Access-Control-Allow-Methods"])
      assert.equal("Content-Type", res.headers["Access-Control-Allow-Headers"])
      assert.equal("*", res.headers["Access-Control-Allow-Origin"])
      assert.not_nil(res.headers["X-Kong-Admin-Latency"])
    end)

    it("returns Kong's version number, edition info and tagline", function()
      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(meta._VERSION, json.version)
      assert.equal(meta._VERSION:match("enterprise") and "enterprise" or "community", json.edition)
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
    it("returns process ids", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
      })
      local body = assert.response(res).has.status(200)
      local json = cjson.decode(body)
      assert.is_table(json.pids)
      assert.matches("%d+", json.pids.master)
      for _, v in pairs(json.pids.workers) do
        assert.matches("%d+", v)
      end
    end)

    it("does not return PRNG seeds", function()
      local res = assert(client:send {
        method = "GET",
        path = "/",
      })
      local body = assert.response(res).has.status(200)
      local json = cjson.decode(body)
      assert.is_nil(json.prng_seeds)
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
    local empty_config_hash = constants.DECLARATIVE_EMPTY_CONFIG_HASH

    it("returns status info", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.is_table(json.server)

      assert.is_number(json.server.connections_accepted)
      assert.is_number(json.server.connections_active)
      assert.is_number(json.server.connections_handled)
      assert.is_number(json.server.connections_reading)
      assert.is_number(json.server.connections_writing)
      assert.is_number(json.server.connections_waiting)
      assert.is_number(json.server.total_requests)
      if strategy == "off" then
        assert.is_equal(empty_config_hash, json.configuration_hash) -- all 0 in DBLESS mode until configuration is applied
        assert.is_nil(json.database)

      else
        assert.is_nil(json.configuration_hash) -- not present in DB mode
        assert.is_table(json.database)
        assert.is_boolean(json.database.reachable)
      end
    end)

    it("returns status info including a configuration_hash in DBLESS mode if an initial configuration has been provided #off", function()
      -- push an initial configuration so that a configuration_hash will be present
      local postres = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = [[
          _format_version: "1.1"
          services:
          - host: "konghq.com"
          ]],
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.res_status(201, postres)

      -- verify the status endpoint now includes a value (other than the default) for the configuration_hash
      local res = assert(client:send {
        method = "GET",
        path = "/status"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)

      if strategy == "off" then
        assert.is_nil(json.database)

      else
        assert.is_table(json.database)
        assert.is_boolean(json.database.reachable)
      end

      assert.is_table(json.server)
      assert.is_number(json.server.connections_accepted)
      assert.is_number(json.server.connections_active)
      assert.is_number(json.server.connections_handled)
      assert.is_number(json.server.connections_reading)
      assert.is_number(json.server.connections_writing)
      assert.is_number(json.server.connections_waiting)
      assert.is_number(json.server.total_requests)
      assert.is_string(json.configuration_hash)
      assert.equal(32, #json.configuration_hash)
      assert.is_not_equal(empty_config_hash, json.configuration_hash)
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

      if strategy == "off" then
        assert.is_nil(json.database)
      else
        assert.is_true(json.database.reachable)
      end
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
        assert.is_table(json.entity_checks)
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

  describe("/schemas/vaults/:name", function()
    it("returns schema of all vaults", function()
      for _, vault in ipairs({"env"}) do
        local res = assert(client:send {
          method = "GET",
          path = "/schemas/vaults/" .. vault,
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.fields)
      end
    end)

    it("returns 404 on a non-existent vault", function()
      local res = assert(client:send {
        method = "GET",
        path = "/schemas/vaults/not-present",
      })
      local body = assert.res_status(404, res)
      local json = cjson.decode(body)
      assert.same({ message = "No vault named 'not-present'" }, json)
    end)

    it("does not return 405 on /schemas/vaults/validate", function()
      local res = assert(client:send {
        method = "POST",
        path = "/schemas/vaults/validate",
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      assert.same("schema violation (name: required field missing)", json.message)
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
    it("returns 200 on a valid plugin schema which contains dot in the key of custom_fields_by_lua", function()
      local res = assert(client:post("/schemas/plugins/validate", {
        body = {
          name = "file-log",
          config = {
            path = "tmp/test",
            custom_fields_by_lua = {
              new_field = "return 123",
              ["request.headers.myheader"] = "return nil",
            },
          },
        },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("schema validation successful", json.message)
    end)
  end)

  describe("/non-existing", function()
    it("returns 404 with HEAD", function()
      local res = assert(client:send {
        method = "HEAD",
        path = "/non-existing"
      })
      local body = assert.res_status(404, res)
      assert.equal("", body)
    end)
    it("returns 404 with OPTIONS", function()
      local res = assert(client:send {
        method = "OPTIONS",
        path = "/non-existing"
      })
      local body = assert.res_status(404, res)
      local json = cjson.decode(body)
      assert.equal("Not found", json.message)
    end)
    it("returns 404 with GET", function()
      local res = assert(client:send {
        method = "GET",
        path = "/non-existing"
      })
      local body = assert.res_status(404, res)
      local json = cjson.decode(body)
      assert.equal("Not found", json.message)
    end)
    it("returns 404 with POST", function()
      local res = assert(client:send {
        method = "POST",
        path = "/non-existing"
      })
      local body = assert.res_status(404, res)
      local json = cjson.decode(body)
      assert.equal("Not found", json.message)
    end)
    it("returns 404 with PUT", function()
      local res = assert(client:send {
        method = "PUT",
        path = "/non-existing"
      })
      local body = assert.res_status(404, res)
      local json = cjson.decode(body)
      assert.equal("Not found", json.message)
    end)
    it("returns 404 with DELETE", function()
      local res = assert(client:send {
        method = "DELETE",
        path = "/non-existing"
      })
      local body = assert.res_status(404, res)
      local json = cjson.decode(body)
      assert.equal("Not found", json.message)
    end)
  end)
end)
end
describe("Admin API - node ID is set correctly", function()
  local client
  local input_node_id = "592e1c2b-6678-45aa-80f9-78cfb29f5e31"
  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    assert(helpers.start_kong {
      node_id = input_node_id
    })
    client = helpers.admin_client(10000)
  end)

  lazy_teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  it("returns node-id set in configuration", function()
    local res1 = assert(client:send {
      method = "GET",
      path = "/"
    })

    local body = assert.res_status(200, res1)
    local json = cjson.decode(body)
    assert.equal(input_node_id, json.node_id)
  end)
end)
