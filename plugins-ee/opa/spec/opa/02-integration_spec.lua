-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local PLUGIN_NAME = "opa"
local OPA_HOST = os.getenv("KONG_SPEC_TEST_OPA_HOST") or "opa"
local OPA_PORT = tonumber(os.getenv("KONG_SPEC_TEST_OPA_PORT_8181")) or 8181
local OPA_SSL_PORT = tonumber(os.getenv("KONG_SPEC_TEST_OPA_PORT_8282")) or 8282


for _, strategy in strategies() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client
    local db_strategy = strategy ~= "off" and strategy or nil

    lazy_setup(function()

      local bp = helpers.get_db_utils(db_strategy, nil, { PLUGIN_NAME })

      local route

      route = bp.routes:insert({
        hosts = { "test1.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/allow1",
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
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
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
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
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
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
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
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
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
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
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
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
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
        },
      }

      route = bp.routes:insert({
        hosts = { "test8.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/allow3",
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
        },
      }

      route = bp.routes:insert({
        hosts = { "test9.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/allow4",
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
          include_body_in_opa_input = true,
        },
      }

      route = bp.routes:insert({
        hosts = { "test10.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/allow5",
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
          include_parsed_json_body_in_opa_input = true,
        },
      }

      route = bp.routes:insert({
        hosts = { "test11.example.com" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_protocol = "https",
          opa_host = OPA_HOST,
          opa_port = OPA_SSL_PORT,
          opa_path = "/v1/data/example/allow3",
          ssl_verify = false,
        }
      }

      route = bp.routes:insert({
                hosts = { "test12.example.com" },
                paths = { "~/request/user1/(?P<user1>\\d+)/" },
                strip_path = false,
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/allow_uri_captures",
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
          include_uri_captures_in_opa_input = true,
        },
      }

      route = bp.routes:insert({
        hosts = { "test13.example.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route.id },
        config = {
          opa_path = "/v1/data/example/opa_message",
          opa_protocol = "http",
          opa_host = OPA_HOST,
          opa_port = OPA_PORT,
        },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = db_strategy,
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
      it("when correct header and path are set", function()
        local r = client:get("/request", {
          headers = {
            host = "test8.example.com",
            ["my-secret-header"] = "open-sesame",
          }
        })
        assert.response(r).has.status(200)
      end)
      it("when raw body is sent to opa and body matches", function()
        local r = client:post("/request", {
          headers = {
            host = "test9.example.com",
            ["Content-Type"] = "application/json",
          },
          body = {
            hello = "world"
          },
        })
        assert.response(r).has.status(200)
      end)
      it("when parsed body is sent to opa, opa accesses key and value matches", function()
        local r = client:post("/request", {
          headers = {
            host = "test10.example.com",
            ["Content-Type"] = "application/json",
          },
          body = {
            hello = "earth"
          },
        })
        assert.response(r).has.status(200)
      end)

      it("fails when opa_protocol is https but no header", function()
        local r = client:post("/request", {
          headers = {
            host = "test11.example.com",
          }
        })

        assert.response(r).has.status(403)
      end)

      it("works when opa_protocol is https and has correct header", function()
        local r = client:post("/request", {
          headers = {
            host = "test11.example.com",
            ["my-secret-header"] = "open-sesame",
          }
        })
        assert.response(r).has.status(200)
      end)

      it("when correct uri captures is sent to opa", function()
        local r = client:get("/request/user1/111222333/", {
          headers = {
            host = "test12.example.com",
          },
        })
        assert.response(r).has.status(200)
      end)
    end)


    describe("denies request", function()
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
      it("when path is not as need in policy", function()
        local r = client:get("/request-wrong", {
          headers = {
            host = "test8.example.com",
            ["my-secret-header"] = "open-sesame",
          }
        })
        assert.response(r).has.status(403)
      end)
      it("when raw body is sent to opa and the string doesn't match", function()
        local r = client:post("/request", {
          headers = {
            host = "test9.example.com",
            ["Content-Type"] = "application/json",
          },
          body = "test",
        })
        assert.response(r).has.status(403)
      end)
      it("when parsed body is sent to opa and it's not json", function()
        local r = client:post("/request", {
          headers = {
            host = "test10.example.com",
            ["Content-Type"] = "application/json",
          },
          body = "test",
        })
        assert.response(r).has.status(403)
      end)
      it("when parsed body is sent to opa, opa accesses key and value doesn't match", function()
        local r = client:post("/request", {
          headers = {
            host = "test10.example.com",
            ["Content-Type"] = "application/json",
          },
          body = {
            hello = "mars"
          },
        })
        assert.response(r).has.status(403)
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

    describe("get false decision", function()
      it("set response message from OPA", function()
        local r = client:get("/request", {
          headers = {
            host = "test13.example.com"
          }
        })

        assert.equal("has-message", r.headers["header-from-opa"])

        local body, _ = assert.res_status(418, r)
        local json = cjson.decode(body)

        assert.equal("Request are rejected", json.message.error)
        assert.equal("OPA Access Control", json.message.source)
      end)
    end)
  end)
end
