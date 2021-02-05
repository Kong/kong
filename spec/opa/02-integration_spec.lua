local helpers = require "spec.helpers"
local cjson = require "cjson"


local PLUGIN_NAME = "opa"


for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()

      local bp = helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })

      local route

      route = bp.routes:insert({
        hosts = { "test1.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/allow1",
          opa_port = 8181,
        },
      }

      route = bp.routes:insert({
        hosts = { "test2.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/deny1",
          opa_port = 8181,
        },
      }

      route = bp.routes:insert({
        hosts = { "test3.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/err1",
          opa_port = 8181,
        },
      }

      route = bp.routes:insert({
        hosts = { "test4.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/err1",
          opa_port = 8181,
        },
      }

      route = bp.routes:insert({
        hosts = { "test5.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/allow2",
          opa_port = 8181,
        },
      }

      route = bp.routes:insert({
        hosts = { "test6.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/deny2",
          opa_port = 8181,
        },
      }

      route = bp.routes:insert({
        hosts = { "test7.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/err2",
          opa_port = 8181,
        },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)


    describe("allows request", function()
      it("when result is true", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.example.com"
          }
        })
        assert.response(r).has.status(200)
      end)
      it("when result.allowed is true and sets header", function()
        local r = client:get("/request", {
          headers = {
            host = "test5.example.com"
          }
        })
        local body, _ = assert.res_status(200, r)
        local json = cjson.decode(body)

        assert.same("yolo",json.headers["header-from-opa"])
      end)
    end)


    describe("denys request", function()
      it("when result is false", function()
        local r = client:get("/request", {
          headers = {
            host = "test2.example.com"
          }
        })
        assert.response(r).has.status(403)
      end)
      it("when result.allowed is false and sets header and status", function()
        local r = client:get("/request", {
          headers = {
            host = "test6.example.com"
          }
        })

        assert.same("yolo-bye",r.headers["header-from-opa"])
      end)
    end)


    describe("throws error", function()
      it("when result is not a boolean", function()
        local r = client:get("/request", {
          headers = {
            host = "test3.example.com"
          }
        })
        assert.response(r).has.status(500)
      end)
      it("when rule doesn't exist in OPA", function()
        local r = client:get("/request", {
          headers = {
            host = "test4.example.com"
          }
        })
        assert.response(r).has.status(500)
      end)
      it("when result.allow is not a boolean", function()
        local r = client:get("/request", {
          headers = {
            host = "test7.example.com"
          }
        })
        assert.response(r).has.status(500)
      end)
    end)
  end)
end
