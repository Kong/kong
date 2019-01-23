local helpers = require "spec.helpers"
local cjson = require "cjson"


local BAD_REGEX = [[(https?:\/\/.*]]  -- illegal regex, errors out


for _, strategy in helpers.each_strategy() do
  describe("Plugin: bot-detection (API) [#" .. strategy .. "]", function()
    local proxy_client
    local route1
    local route2

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      route1 = bp.routes:insert {
        hosts = { "bot1.com" },
      }

      route2 = bp.routes:insert {
        hosts = { "bot2.com" },
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.admin_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("fails when whitelisting a bad regex", function()
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/plugins/",
        body    = {
          name                 = "bot-detection",
          config = { whitelist = { BAD_REGEX } },
          route = { id = route1.id }
        },
        headers = {
          ["content-type"] = "application/json"
        }
      })
      local body = assert.response(res).has.status(400)
      local json = cjson.decode(body)
      assert.same("schema violation", json.name)
      assert.same({ "not a valid regex: " .. BAD_REGEX }, json.fields.config.whitelist)
    end)

    it("fails when blacklisting a bad regex", function()
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/plugins/",
        body    = {
          name                 = "bot-detection",
          config = { whitelist = { BAD_REGEX } },
          route = { id = route2.id }
        },
        headers = {
          ["content-type"] = "application/json"
        }
      })
      assert.response(res).has.status(400)
    end)
  end)
end
