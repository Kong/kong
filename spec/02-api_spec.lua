local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("rate-limiting-advanced API", function()
  local admin_client, bp

  setup(function()
    bp = helpers.get_db_utils(nil, nil, {"rate-limiting-advanced"})

    assert(bp.routes:insert {
      name  = "test",
      hosts = { "test1.com" },
    })

    assert(helpers.start_kong({
      plugins = "rate-limiting-advanced",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    admin_client = helpers.admin_client()
  end)

  teardown(function()
    if admin_client then
      admin_client:close()
    end
    helpers.stop_kong(nil, true)
  end)

  describe("POST", function()
    it("errors with size/limit mismatch", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/test/plugins/",
        body = {
          name = "rate-limiting-advanced",
          config = {
            window_size = { 10, 60 },
            limit = { 10 },
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.same("You must provide the same number of windows and limits", body.fields["@entity"][1])
    end)

    it("errors with missing size/limit configs", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/test/plugins/",
        body = {
          name = "rate-limiting-advanced",
          config = {
            limit = { 10 },
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.same("required field missing", body.fields.config.window_size)
    end)

    it("transparently sorts limit/window_size pairs", function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = "rate-limiting-advanced",
          config = {
            window_size = { 3600, 60 },
            limit = { 100, 10 },
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      table.sort(json.config.limit)
      table.sort(json.config.window_size)

      assert.same({ 10, 100 }, json.config.limit)
      assert.same({ 60, 3600 }, json.config.window_size)
    end)
  end)

  describe("PATCH", function()
    local plugin_id

    setup(function()
      local res = assert(admin_client:send {
        method = "POST",
        path = "/routes/test/plugins/",
        body = {
          name = "rate-limiting-advanced",
          config = {
            window_size = { 10 },
            limit = { 10 },
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(201, res)
      plugin_id = cjson.decode(body).id
    end)

    it("errors with size/limit mismatch", function()
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/routes/test/plugins/" .. plugin_id,
        body = {
          name = "rate-limiting-advanced",
          config = {
            window_size = { 10, 60 },
            limit = { 10 },
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(400, res))
      assert.same("You must provide the same number of windows and limits", body.fields["@entity"][1])
    end)

    it("accepts an update without requiring size/limit configs", function()
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/routes/test/plugins/" .. plugin_id,
        body = {
          name = "rate-limiting-advanced",
          config = {
            sync_rate = 10,
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.same(10, body.config.limit[1])
      assert.same(10, body.config.window_size[1])
    end)

    it("accepts an update chaings size/limit configs", function()
      local res = assert(admin_client:send {
        method = "PATCH",
        path = "/routes/test/plugins/" .. plugin_id,
        body = {
          name = "rate-limiting-advanced",
          config = {
            window_size = { 20 },
            limit = { 20 },
          }
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local body = cjson.decode(assert.res_status(200, res))
      assert.same(20, body.config.limit[1])
      assert.same(20, body.config.window_size[1])

      -- check that sync_rate, which we touched before, it still the same
      assert.same(10, body.config.sync_rate)
    end)
  end)
end)
