local helpers = require "spec.helpers"


local function create_big_data(size)
  return {
    mock_json = {
      big_field = string.rep("*", size),
    },
  }
end


for _, strategy in helpers.each_strategy() do
  describe("Plugin: response-transformer [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route = bp.routes:insert({
        hosts   = { "response.com" },
        methods = { "POST" },
      })

      bp.plugins:insert {
        route = { id = route.id },
        name     = "response-transformer",
        config   = {
          add    = {
            json = {"p1:v1"},
          },
          remove = {
            json = {"params"},
          }
        },
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
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
    end)

    it("add new parameters on large POST", function()
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/post",
        body    = create_big_data(1024 * 1024),
        headers = {
          host             = "response.com",
          ["content-type"] = "application/json",
        }
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.equal("v1", json.p1)
    end)

    it("remove parameters on large POST", function()
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/post",
        body    = create_big_data(1024 * 1024),
        headers = {
          host             = "response.com",
          ["content-type"] = "application/json",
        }
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.is_nil(json.params)
    end)
  end)
end
