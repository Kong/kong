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
      db.event_hooks:insert({
        event = "foo", source = "bar", handler = "log", config = {}
      })
      local res  = client:get("/event-hooks")
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal(1, #json.data)
    end)

    it("POST", function()
      local res = client:post("/event-hooks", {
        body = {
          event = "foo",
          source = "bar",
          handler = "log",
          config = {},
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      assert.res_status(201, res)
    end)

    describe("/event-hooks/sources", function()
      it("exists", function()
        local res = client:get("/event-hooks/sources")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same({ data = {} }, json)
      end)

      pending("lists available sources", function()
        -- need to provide kong with some mocks that publish events
        -- unless we add some already to kong
      end)
    end)

    describe("/event-hooks/<some id>", function()
      local event_hook

      before_each(function()
        event_hook = db.event_hooks:insert({
          event = "foo", source = "bar", handler = "log", config = {}
        })
      end)

      it("GET", function()
        local res  = client:get("/event-hooks/" .. event_hook.id)
        assert.res_status(200, res)
      end)

      it("PATCH", function()
        local res  = client:patch("/event-hooks/" .. event_hook.id, {
          body = {
            source = "baz",
          },
          headers = { ["Content-Type"] = "application/json" },
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("baz", json.source)
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
