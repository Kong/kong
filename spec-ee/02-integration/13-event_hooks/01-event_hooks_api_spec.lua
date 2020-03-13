local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("/event-hooks with DB: #" .. strategy, function()
    local client, _, db

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, {
        "event_hooks"
      })

      assert(helpers.start_kong {
        database = strategy,
        event_hooks_enabled = true,
      })

      client = assert(helpers.admin_client(10000))

    end)

    before_each(function()
      db:truncate("event_hooks")
    end)

    it("GET", function()
      local res = client:post("/event-hooks/", {
      body = {
          source = "dao:crud",
          event = "create",
          handler = "log",
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      assert.res_status(201, res)

      local res  = client:get("/event-hooks")
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(1, #json.data)
    end)

    it("POST", function()
      local res = client:post("/event-hooks", {
        body = {
          event = "create",
          source = "dao:crud",
          handler = "log",
          config = {},
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      assert.res_status(201, res)
    end)

    describe("/event-hooks/sources", function()
      it("lists available sources", function()
        local res = client:get("/event-hooks/sources")
        local body = assert.res_status(200, res)
        local sources = cjson.decode(body).data
        local crud_fields = {
          fields = { "operation", "entity", "old_entity", "schema" },
        }
        local some_sources = {
          ["balancer"] = {
            ["health"] = {
              fields = { "upstream_id", "ip", "port", "hostname", "health" },
            }
          },
          ["crud"] = {
            ["consumers"] = crud_fields,
            ["consumers:create"] = crud_fields,
            ["consumers:update"] = crud_fields,
            ["consumers:delete"] = crud_fields,
          }
        }

        -- no need to compare with everything, just that some of them are in
        -- there?
        for source, events in pairs(some_sources) do
          assert.not_nil(sources[source])
          for event, event_data in pairs(events) do
            assert.same(event_data, sources[source][event])
          end
        end
      end)
    end)

    describe("/event-hooks/<some id> #foo", function()
      local event_hook

      before_each(function()
        local res = client:post("/event-hooks/", {
          body = {
            source = "dao:crud",
            event = "create",
            handler = "log",
          },
          headers = { ["Content-Type"] = "application/json" },
        })
        local body = assert.res_status(201, res)
        event_hook = cjson.decode(body)
      end)

      it("GET", function()
        local res  = client:get("/event-hooks/" .. event_hook.id)
        assert.res_status(200, res)
      end)

      it("PATCH", function()
        local res  = client:patch("/event-hooks/" .. event_hook.id, {
          body = {
            event = "update",
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("update", json.event)
      end)

      it("DELETE", function()
        local res  = client:delete("/event-hooks/" .. event_hook.id)
        assert.res_status(204, res)
      end)

      pending("/event-hooks/<some id>/ping", function()

      end)

      pending("/event-hooks/<some id>/test", function()

      end)
    end)

    lazy_teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)
  end)
end
