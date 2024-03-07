-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  local proxy_client
  local db_strategy = strategy ~= "off" and strategy or nil
  local body_schema = [[
    [
      {
        "f1": {
          "type": "string",
          "required": true
        }
      }
    ]
  ]]

  local param_schema = {
    {
      name = "x-kong-name",
      ["in"] = "header",
      required = true,
      schema = '{"type": "array", "items": {"type": "integer"}}',
      style = "simple",
      explode = false,
    }
  }

  describe("Plugin: request-validator (failure log) [#" .. strategy .. "]", function()
    lazy_setup(function()
      local bp = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
      }, { "request-validator" })

      local function add_plugin(route, config)
        assert(bp.plugins:insert {
          route = { id = route.id },
          name = "request-validator",
          config = config,
        })
      end

      local route1 = assert(bp.routes:insert {
        paths = {"/body"}
      })
      add_plugin(route1, {
        body_schema = body_schema,
      })
      local route2 = assert(bp.routes:insert {
        paths = {"/body-verbose"}
      })
      add_plugin(route2, {
        body_schema = body_schema,
        verbose_response = true,
      })
      local route3 = assert(bp.routes:insert {
        paths = {"/content"}
      })
      add_plugin(route3, {
        body_schema = body_schema,
        allowed_content_types = { "application/json", },
      })
      local route4 = assert(bp.routes:insert {
        paths = {"/content-verbose"}
      })
      add_plugin(route4, {
        body_schema = body_schema,
        allowed_content_types = { "application/json", },
        verbose_response = true,
      })
      local route5 = assert(bp.routes:insert {
        paths = {"/param"}
      })
      add_plugin(route5, {
        parameter_schema = param_schema,
      })
      local route6 = assert(bp.routes:insert {
        paths = {"/param-verbose"}
      })
      add_plugin(route6, {
        parameter_schema = param_schema,
        verbose_response = true,
      })

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database = db_strategy,
        plugins = "request-validator",
      }))

      proxy_client = helpers.proxy_client()
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong()
    end)

    before_each(function()
      helpers.clean_logfile()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("body_schema", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/body",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          f1 = "value!"
        }
      })
      assert.res_status(200, res)

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/body",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
        }
      })
      local json = cjson.decode(assert.res_status(400, res))
      local message = "request body doesn't conform to schema"
      assert.same(message, json.message)
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line(message, true)
    end)

    it("body_schema & verbose_respnse", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/body-verbose",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          f1 = "value!"
        }
      })
      assert.res_status(200, res)

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/body-verbose",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
        }
      })
      local json = cjson.decode(assert.res_status(400, res))
      local message = "required field missing"
      assert.same(message, json.message.f1)
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line(message, true)
    end)

    it("allowed_content_types", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/content",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          f1 = "value!"
        }
      })
      assert.response(res).has.status(200)

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/content",
        headers = {
          ["Content-Type"] = "application/xml",
        },
        body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      })
      local json = cjson.decode(assert.res_status(400, res))
      local message = "request body doesn't conform to schema"
      assert.same(message, json.message)
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line(message, true)
    end)

    it("allowed_content_types & verbose_response", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/content-verbose",
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = {
          f1 = "value!"
        }
      })
      assert.response(res).has.status(200)

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/content-verbose",
        headers = {
          ["Content-Type"] = "application/xml",
        },
        body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      })
      local json = cjson.decode(assert.res_status(400, res))
      local message = "specified Content-Type is not allowed"
      assert.same(message, json.message)
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line(message, true)
    end)

    it("parameter_schema", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/param",
        headers = {
          ["Content-Type"] = "application/json",
          ["x-kong-name"] = "1,2,3",
        },
      })
      assert.res_status(200, res)

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/param",
        headers = {
          ["Content-Type"] = "application/json",
          ["x-kong-name"] = "a,b,c",
        },
      })
      assert.res_status(400, res)
      local json = cjson.decode(assert.res_status(400, res))
      local message = "request param doesn't conform to schema"
      assert.same(message, json.message)
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line(message, true)
    end)

    it("parameter_schema & verbose_response", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/param-verbose",
        headers = {
          ["Content-Type"] = "application/json",
          ["x-kong-name"] = "1,2,3",
        },
      })
      assert.res_status(200, res)

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/param-verbose",
        headers = {
          ["Content-Type"] = "application/json",
          ["x-kong-name"] = "a,b,c",
        },
      })
      assert.res_status(400, res)
      local json = cjson.decode(assert.res_status(400, res))
      local message = "header 'x-kong-name' validation failed, [error] failed to validate item 1: wrong type: expected integer, got string"
      assert.same(message, json.message)
      assert.logfile().has.no.line("^\\d{4}/\\d{2}/\\d{2} \\d{2}:\\d{2}:\\d{2} \\[error\\]", false)
      assert.logfile().has.line(message, true)
    end)
  end)
end
