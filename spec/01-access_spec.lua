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
  return kong.response.exit(406, { message = "Invalid" })
]]

local mock_fn_four = [[
  ngx.status = 400
]]

local mock_fn_five = [[
  ngx.exit(ngx.status)
]]

local mock_fn_six = [[
  local count = 0
  return function()
      count = count + 1
      ngx.status = 200
      ngx.say(ngx.worker.pid() * 1000 + count)
      ngx.exit(ngx.status)
    end
]]



describe("Plugin: serverless-functions", function()
  it("priority of plugins", function()
    local pre = require "kong.plugins.pre-function.handler"
    local post = require "kong.plugins.post-function.handler"
    assert(pre.PRIORITY > post.PRIORITY, "expected the priority of PRE (" ..
           tostring(pre.PRIORITY) .. ") to be higher than POST (" ..
           tostring(post.PRIORITY)..")")
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

      local route6 = bp.routes:insert {
        service = { id = service.id },
        hosts   = { "six." .. plugin_name .. ".com" },
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

      bp.plugins:insert {
        name    = plugin_name,
        route   = { id = route6.id },
        config  = {
          functions = { mock_fn_six }
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

      it("with upvalues", function()
        local results = {}
        for i = 1, 50 do
          local res = assert(client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Host"] = "six." .. plugin_name .. ".com"
            }
          })

          local body = assert.res_status(200, res)
          assert.is_string(body)
          assert.is_nil(results[body])
          results[body] = nil
        end
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
