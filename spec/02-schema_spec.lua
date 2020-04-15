local helpers = require "spec.helpers"
local cjson = require "cjson"

local PLUGIN_NAME = "upstream-timeout"

for _, strategy in helpers.each_strategy() do
  describe("Plugin API config validator:", function()
    local admin_client

    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "plugins"
      })

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled, upstream-timeout"
      })

      admin_client = helpers.admin_client()
    end)

    lazy_teardown(function()
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    local function make_request(client, conf)
      return (client:send {
        method = "POST",
        path = "/plugins",
        body = {
          name = PLUGIN_NAME,
          config = conf,
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
    end

    it("fails when timeout conf is not a positive integer", function()
      local res = assert(make_request(admin_client, { read_timeout = "invalid_string_type" }))

      local body = assert.response(res).has.status(400)
      local json = cjson.decode(body)
      assert.same(json.name, "schema violation")

      res = assert(make_request(admin_client, { read_timeout = -2342 }))
      assert.response(res).has.status(400)
      assert.same(json.name, "schema violation")
    end)

    it("succeeds if positive integer", function()
      local res = assert(make_request(admin_client, { read_timeout = 500 }))
      local body = assert.response(res).has.status(201)
      local json = cjson.decode(body)
      assert.same(json.config.read_timeout, 500)
    end)

  end)
end
