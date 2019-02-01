local helpers = require "spec.helpers"
local cjson   = require "cjson"


for _, strategy in helpers.each_strategy() do

describe("Plugin: acl (run_on) [#" .. strategy .. "]", function()
  local admin_client

  lazy_setup(function()
    helpers.get_db_utils(strategy, {})

    assert(helpers.start_kong({
      database = strategy,
    }))

    admin_client = helpers.admin_client()
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    admin_client = helpers.admin_client()
  end)

  after_each(function ()
    admin_client:close()
  end)

  describe("run_on parameter", function()
    it("supports 'first'", function()
      local res = assert(admin_client:post("/plugins", {
        headers = { ["Content-Type"] = "application/json" },
        body = {
          run_on = "first",
          name = "acl",
          config = {
            whitelist = { "users" }
          }
        }
      }))

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      assert.equal("first", json.run_on)
    end)

    it("doesn't support 'second'", function()
      local res = assert(admin_client:post("/plugins", {
        headers = { ["Content-Type"] = "application/json" },
        body = {
          run_on = "second",
          name = "acl",
          config = {
            whitelist = { "users" }
          }
        },
      }))

      local body = assert.res_status(400, res)
      local json = cjson.decode(body)

      assert.same({
        code = 2,
        fields = {
          run_on = "expected one of: first"
        },
        message = "schema violation (run_on: expected one of: first)",
        name = "schema violation"
      }, json)

    end)
  end)

  it("doesn't support 'all'", function()
    local res = assert(admin_client:post("/plugins", {
      headers = { ["Content-Type"] = "application/json" },
      body = {
        run_on = "all",
        name = "acl",
        config = {
          whitelist = { "users" }
        }
      },
    }))

    local body = assert.res_status(400, res)
    local json = cjson.decode(body)

    assert.same({
      code = 2,
      fields = {
        run_on = "expected one of: first"
      },
      message = "schema violation (run_on: expected one of: first)",
      name = "schema violation"
    }, json)
  end)

end)

end
