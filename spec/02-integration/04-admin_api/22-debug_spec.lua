local helpers = require "spec.helpers"
local cjson = require "cjson"

local strategies = {}
for _, strategy in helpers.each_strategy() do
  table.insert(strategies, strategy)
end
table.insert(strategies, "off")
for _, strategy in pairs(strategies) do
describe("Admin API - Kong routes with strategy #" .. strategy, function()
  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    assert(helpers.start_kong {
      database = strategy,
      db_update_propagation = strategy == "cassandra" and 1 or 0,
    })
    assert(helpers.start_kong{
      database = strategy,
      prefix = "node2",
      db_update_propagation = strategy == "cassandra" and 1 or 0,
      admin_listen = "127.0.0.1:9110",
      admin_gui_listen = "off",
      proxy_listen = "off",
      log_level = "debug",
    })

    if strategy ~= "off" then
      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        db_update_frequency = 0.1,
        admin_listen = "127.0.0.1:9113",
        cluster_listen = "127.0.0.1:9005",
        admin_gui_listen = "off",
        prefix = "cp",
        log_level = "debug",
      }))
      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        db_update_frequency = 0.1,
        admin_listen = "127.0.0.1:9114",
        cluster_listen = "127.0.0.1:9006",
        admin_gui_listen = "off",
        prefix = "cp2",
        cluster_telemetry_listen = "localhost:9008",
        log_level = "debug",
      }))
    end
  end)

  lazy_teardown(function()
    helpers.stop_kong()
    helpers.stop_kong("node2")

    if strategy ~= "off" then
      helpers.stop_kong("cp")
      helpers.stop_kong("cp2")
    end
  end)

  describe("/debug/{node, cluster}/log-level", function()
    it("gets current log level for traditional and dbless", function()
      local res = assert(helpers.admin_client():send {
        method = "GET",
        path = "/debug/node/log-level",
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local message = "log level: debug"
      assert(json.message == message)
    end)

    if strategy == "off" then
      it("cannot change the log level for dbless", function()
        local res = assert(helpers.admin_client():send {
          method = "PUT",
          path = "/debug/node/log-level/notice",
        })
        local body = assert.res_status(405, res)
        local json = cjson.decode(body)
        local message = "cannot change log level when not using a database"
        assert(json.message == message)
      end)
      return
    end

    it("changes log level for traditional mode", function()
      local res = assert(helpers.admin_client():send {
        method = "PUT",
        path = "/debug/node/log-level/notice",
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      local message = "log level changed"
      assert(json.message == message)

      -- make sure we changed to notice
      res = assert(helpers.admin_client():send {
        method = "GET",
        path = "/debug/node/log-level",
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      message = "log level: notice"
      assert(json.message == message)

      -- go back to default (debug)
      res = assert(helpers.admin_client():send {
        method = "PUT",
        path = "/debug/node/log-level/debug",
      })
      body = assert.res_status(201, res)
      json = cjson.decode(body)
      message = "log level changed"
      assert(json.message == message)

      -- make sure we changed to debug
      res = assert(helpers.admin_client():send {
        method = "GET",
        path = "/debug/node/log-level",
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      message = "log level: debug"
      assert(json.message == message)
    end)

    it("handles unknown log level for traditional mode", function()
      local res = assert(helpers.admin_client():send {
        method = "PUT",
        path = "/debug/node/log-level/stderr",
      })
      local body = assert.res_status(400, res)
      local json = cjson.decode(body)
      local message = "unknown log level"
      assert(json.message == message)
    end)

    it("current log level is equal to configured log level", function()
      local res = assert(helpers.admin_client():send {
        method = "PUT",
        path = "/debug/node/log-level/debug",
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local message = "log level is already debug"
      assert(json.message == message)
    end)

    it("broadcasts to all traditional nodes", function()
      local res = assert(helpers.admin_client():send {
        method = "PUT",
        path = "/debug/cluster/log-level/emerg"
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      local message = "log level changed"
      assert(json.message == message)

      -- make sure we changed to emerg on NODE 1
      res = assert(helpers.admin_client():send {
        method = "GET",
        path = "/debug/node/log-level",
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      message = "log level: emerg"
      assert(json.message == message)

      -- Wait for NODE 2 to check for cluster events
      helpers.wait_until(function()
        -- make sure we changed to emerg on NODE 2
        res = assert(helpers.admin_client(nil, 9110):send {
          method = "GET",
          path = "/debug/node/log-level",
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        message = "log level: emerg"
        return json.message == message
      end, 30)

      -- decrease log level to debug on both NODE 1 and NODE 2
      res = assert(helpers.admin_client():send {
        method = "PUT",
        path = "/debug/cluster/log-level/debug"
      })
      body = assert.res_status(201, res)
      json = cjson.decode(body)
      message = "log level changed"
      assert(json.message == message)

      -- make sure we changed to debug on NODE 1
      res = assert(helpers.admin_client():send {
        method = "GET",
        path = "/debug/node/log-level",
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      message = "log level: debug"
      assert(json.message == message)

      -- Wait for NODE 2 to check for cluster events
      helpers.wait_until(function()
        -- make sure we changed to debug on NODE 2
        res = assert(helpers.admin_client(nil, 9110):send {
          method = "GET",
          path = "/debug/node/log-level",
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        message = "log level: debug"
        return json.message == message
      end, 30)
    end)

    it("gets current log level for CP", function()
      local res = assert(helpers.admin_client(nil, 9113):send {
        method = "GET",
        path = "/debug/node/log-level",
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      local message = "log level: debug"
      assert(json.message == message)
    end)

    it("changes CP log level", function()
      local res = assert(helpers.admin_client(nil, 9113):send {
        method = "PUT",
        path = "/debug/node/log-level/notice",
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      local message = "log level changed"
      assert(json.message == message)

      -- make sure we changed to notice
      res = assert(helpers.admin_client(nil, 9113):send {
        method = "GET",
        path = "/debug/node/log-level",
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      message = "log level: notice"
      assert(json.message == message)

      -- go back to default (debug)
      res = assert(helpers.admin_client(nil, 9113):send {
        method = "PUT",
        path = "/debug/node/log-level/debug",
      })
      body = assert.res_status(201, res)
      json = cjson.decode(body)
      message = "log level changed"
      assert(json.message == message)

      -- make sure we changed to debug
      res = assert(helpers.admin_client(nil, 9113):send {
        method = "GET",
        path = "/debug/node/log-level",
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      message = "log level: debug"
      assert(json.message == message)
    end)

    it("broadcasts to all CP nodes", function()
      local res = assert(helpers.admin_client(nil, 9113):send {
        method = "PUT",
        path = "/debug/cluster/control-planes-nodes/log-level/emerg"
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      local message = "log level changed"
      assert(json.message == message)

      -- make sure we changed to emerg on CP 1
      res = assert(helpers.admin_client(nil, 9113):send {
        method = "GET",
        path = "/debug/node/log-level",
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      message = "log level: emerg"
      assert(json.message == message)

      -- Wait for CP 2 to check for cluster events
      helpers.wait_until(function()
        -- make sure we changed to emerg on CP 2
        res = assert(helpers.admin_client(nil, 9114):send {
          method = "GET",
          path = "/debug/node/log-level",
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        message = "log level: emerg"
        return json.message == message
      end, 30)

      -- decrease log level to debug on both CP 1 and CP 2
      res = assert(helpers.admin_client(nil, 9113):send {
        method = "PUT",
        path = "/debug/cluster/control-planes-nodes/log-level/debug"
      })
      body = assert.res_status(201, res)
      json = cjson.decode(body)
      message = "log level changed"
      assert(json.message == message)

      -- make sure we changed to debug on CP 1
      res = assert(helpers.admin_client(nil, 9113):send {
        method = "GET",
        path = "/debug/node/log-level",
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      message = "log level: debug"
      assert(json.message == message)

      -- Wait for CP 2 to check for cluster events
      helpers.wait_until(function()
        -- make sure we changed to debug on CP 2
        res = assert(helpers.admin_client(nil, 9114):send {
          method = "GET",
          path = "/debug/node/log-level",
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)
        message = "log level: debug"
        return json.message == message
      end, 30)
    end)

    it("common cluster endpoint not accepted in hybrid mode", function()
      local res = assert(helpers.admin_client(nil, 9113):send {
        method = "PUT",
        path = "/debug/cluster/log-level/notice"
      })
      assert.res_status(404, res)
    end)

    it("newly spawned workers can update their log levels", function()
      local res = assert(helpers.admin_client():send {
        method = "PUT",
        path = "/debug/node/log-level/crit",
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      local message = "log level changed"
      assert(json.message == message)

      -- make sure we changed to crit
      res = assert(helpers.admin_client():send {
        method = "GET",
        path = "/debug/node/log-level",
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      message = "log level: crit"
      assert(json.message == message)

      local prefix = helpers.test_conf.prefix
      assert(helpers.reload_kong(strategy, "reload --prefix " .. prefix))

      -- Wait for new workers to spawn
      helpers.wait_until(function()
        -- make sure new workers' log level is crit
        res = assert(helpers.admin_client():send {
          method = "GET",
          path = "/debug/node/log-level",
        })
        body = assert.res_status(200, res)
        json = cjson.decode(body)

        message = "log level: crit"
        return json.message == message
      end, 30)
    end)
  end)
end)
end
