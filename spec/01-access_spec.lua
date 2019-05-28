local helpers = require "spec.helpers"
local cjson = require "cjson"

local mock_fn_one = [[
  ngx.status = 503
  ngx.exit(ngx.status)
]]

local mock_fn_two = [[
  ngx.status = 404
  ngx.say("Not Found")
  ngx.exit(ngx.status)
]]

local mock_fn_three = [[
  local responses = require "kong.tools.responses"
  return responses.send(406, "Invalid")
]]

local mock_fn_four = [[
  ngx.status = 400
]]

local mock_fn_five = [[
  ngx.exit(ngx.status)
]]



describe("Plugin: serverless-functions", function()
  it("priority of plugins", function()
    local pre = require "kong.plugins.pre-function.handler"
    local post = require "kong.plugins.pre-function.handler"
    assert(pre.PRIORITY > post.PRIORITY, "expected the priority of PRE to be higher than POST")
  end)
end)



for _, plugin_name in ipairs({ "pre-function", "post-function" }) do

  describe("Plugin: " .. plugin_name .. " (access)", function()
    local client, admin_client

    setup(function()
      local bp, db = helpers.get_db_utils()

      assert(db:truncate())

      local service = bp.services:insert {
        name     = "service-1",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route1 = bp.routes:insert {
        service = { id = service.id },
        hosts   = { "one." .. plugin_name .. ".com" },
      }

      local route2 = bp.routes:insert {
        service = { id = service.id },
        hosts   = { "two." .. plugin_name .. ".com" },
      }

      local route3 = bp.routes:insert {
        service = { id = service.id },
        hosts   = { "three." .. plugin_name .. ".com" },
      }

      local route4 = bp.routes:insert {
        service = { id = service.id },
        hosts   = { "four." .. plugin_name .. ".com" },
      }

      bp.plugins:insert {
        name    = plugin_name,
        route   = { id = route1.id },
        config  = {
          functions = { mock_fn_one }
        },
      }

      bp.plugins:insert {
        name    = plugin_name,
        route   = { id = route2.id },
        config  = {
          functions = { mock_fn_two }
        },
      }

      bp.plugins:insert {
        name    = plugin_name,
        route   = { id = route3.id },
        config  = {
          functions = { mock_fn_three }
        },
      }

      bp.plugins:insert {
        name    = plugin_name,
        route   = { id = route4.id },
        config  = {
          functions = { mock_fn_four, mock_fn_five }
        },
      }

      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    teardown(function()
      if client and admin_client then
        client:close()
        admin_client:close()
      end
      helpers.stop_kong()
    end)

    describe("request termination", function()
      it("using ngx.exit()", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "one." .. plugin_name .. ".com"
          }
        })

        assert.res_status(503, res)
      end)

      it("using ngx.status and exit", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "two." .. plugin_name .. ".com"
          }
        })
        local body = assert.res_status(404, res)
        assert.same("Not Found", body)
      end)

      it("import response utility and send message", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "three." .. plugin_name .. ".com"
          }
        })
        local body = assert.res_status(406, res)
        local json = cjson.decode(body)
        assert.same({ message = "Invalid" }, json)
      end)

      it("cascading functions for a 400 and exit", function()
        local res = assert(client:send {
          method = "GET",
          path = "/status/200",
          headers = {
            ["Host"] = "four." .. plugin_name .. ".com"
          }
        })
        local body = assert.res_status(400, res)
        assert.same("Bad request", body)
      end)
    end)
  end)

end
