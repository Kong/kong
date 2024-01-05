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
  ngx.log(ngx.ERR, "mock_fn_six: initialization ran")
  return function()
      ngx.log(ngx.ERR, "mock_fn_six: function ran")
      count = count + 1
      ngx.status = 200
      ngx.say(ngx.worker.pid() * 1000 + count)
      ngx.exit(ngx.status)
    end
]]

local mock_fn_seven = [[
  ngx.req.read_body()

  local count = tonumber(ngx.req.get_body_data())
  count = count + 1

  ngx.status = 200
  ngx.say(count)
  ngx.exit(ngx.status)
]]

-- same as 7, but with upvalue format
local mock_fn_eight = "return function() \n" .. mock_fn_seven .. "\n end"

local mock_fn_nine = [[
  error("this should stop the request with a 500")
]]

local mock_fn_ten = [[
  ngx.var.args = nil
]]

-- cache is accessible
local mock_fn_eleven = [[
  local ok, err = kong.cache:get("foo", nil, function() return "val" end)
  if err then
    ngx.exit(500)
  end
  local v = kong.cache:get("foo")
  ngx.status = 200
  ngx.say(v)
  ngx.exit(ngx.status)
]]

-- cache does not allow access to gateway information
local mock_fn_twelve = [[
  ngx.status = 200
  ngx.say(tostring(kong.cache.cluster_events))
  ngx.exit(ngx.status)
]]

-- configuration is accessible
local mock_fn_thirteen = [[
  ngx.status = 200
  ngx.say(kong.configuration.plugins[1])
  ngx.exit(ngx.status)
]]

-- configuration restricts access to properties
local mock_fn_fourteen = [[
  ngx.status = 200
  ngx.say(kong.configuration.pg_password)
  ngx.exit(ngx.status)
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

  for _, method in ipairs({ "phase=functions" }) do
    local function get_conf(functions)
      return { access = functions }
    end

    describe("Plugin: " .. plugin_name .. string.format(" (by %s)", method) .. " access", function()
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
          hosts   = { "one." .. plugin_name .. ".test" },
        }

        local route2 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "two." .. plugin_name .. ".test" },
        }

        local route3 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "three." .. plugin_name .. ".test" },
        }

        local route4 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "four." .. plugin_name .. ".test" },
        }

        local route6 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "six." .. plugin_name .. ".test" },
        }

        local route7 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "seven." .. plugin_name .. ".test" },
        }

        local route8 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "eight." .. plugin_name .. ".test" },
        }

        local route9 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "nine." .. plugin_name .. ".test" },
        }

        local route10 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "ten." .. plugin_name .. ".test" },
        }

        local route11 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "eleven." .. plugin_name .. ".test" },
        }

        local route12 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "twelve." .. plugin_name .. ".test" },
        }

        local route13 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "thirteen." .. plugin_name .. ".test" },
        }

        local route14 = bp.routes:insert {
          service = { id = service.id },
          hosts   = { "fourteen." .. plugin_name .. ".test" },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route1.id },
          config  = get_conf { mock_fn_one },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route2.id },
          config  = get_conf { mock_fn_two },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route3.id },
          config  = get_conf { mock_fn_three },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route4.id },
          config  = get_conf { mock_fn_four, mock_fn_five },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route6.id },
          config  = get_conf { mock_fn_six },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route7.id },
          config  = get_conf { mock_fn_seven },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route8.id },
          config  = get_conf { mock_fn_eight },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route9.id },
          config  = get_conf { mock_fn_nine },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route10.id },
          config  = get_conf { mock_fn_ten },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route11.id },
          config  = get_conf { mock_fn_eleven },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route12.id },
          config  = get_conf { mock_fn_twelve },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route13.id },
          config  = get_conf { mock_fn_thirteen },
        }

        bp.plugins:insert {
          name    = plugin_name,
          route   = { id = route14.id },
          config  = get_conf { mock_fn_fourteen },
        }

        assert(helpers.start_kong({
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))
      end)

      teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        client = helpers.proxy_client()
        admin_client = helpers.admin_client()
      end)

      after_each(function()
        if client and admin_client then
          client:close()
          admin_client:close()
        end
      end)


      describe("request termination", function()
        it("using ngx.exit()", function()
          local res = assert(client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Host"] = "one." .. plugin_name .. ".test"
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
                ["Host"] = "six." .. plugin_name .. ".test"
              }
            })

            local body = assert.res_status(200, res)
            assert.is_string(body)
            --print(i, ": ", body)
            assert.is_nil(results[body])
            results[body] = true
          end
        end)

        it("using ngx.status and exit", function()
          local res = assert(client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Host"] = "two." .. plugin_name .. ".test"
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
              ["Host"] = "three." .. plugin_name .. ".test"
            }
          })
          local body = assert.res_status(406, res)
          local json = cjson.decode(body)
          assert.not_nil(json)
          assert.matches("Invalid", json.message)
        end)

        it("cascading functions for a 400 and exit", function()
          local res = assert(client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Host"] = "four." .. plugin_name .. ".test"
            }
          })
          local body = assert.res_status(400, res)
          assert.matches("Bad request", body)
        end)

        it("runtime error aborts with a 500", function()
          local res = assert(client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Host"] = "nine." .. plugin_name .. ".test"
            }
          })
          local body = assert.res_status(500, res)
          local json = cjson.decode(body)
          assert.not_nil(json)
          assert.matches("An unexpected error occurred", json.message)
        end)
      end)

      describe("invocation count", function()
        it("once on initialization", function()
          local count = 0
          local res = assert(client:send {
            method = "POST",
            path = "/status/200",
            headers = {
              ["Host"] = "seven." .. plugin_name .. ".test",
              ["Content-Length"] = #tostring(count),
            },
            body = count,
          })
          assert.equal(1, tonumber(res:read_body()))
        end)

        it("on repeated calls", function()
          local count = 0

          for i = 1, 10 do
            local res = assert(client:send {
              method = "POST",
              path = "/status/200",
              headers = {
                ["Host"] = "seven." .. plugin_name .. ".test",
                ["Content-Length"] = #tostring(count),
              },
              body = count,
            })
            count = tonumber(res:read_body())
          end

          assert.equal(10, count)
        end)

        it("once on initialization, with upvalues", function()
          local count = 0
          local res = assert(client:send {
            method = "POST",
            path = "/status/200",
            headers = {
              ["Host"] = "eight." .. plugin_name .. ".test",
              ["Content-Length"] = #tostring(count),
            },
            body = count,
          })
          assert.equal(1, tonumber(res:read_body()))
        end)

        it("on repeated calls, with upvalues", function()
          local count = 0
          for i = 1, 10 do
            local res = assert(client:send {
              method = "POST",
              path = "/status/200",
              headers = {
                ["Host"] = "eight." .. plugin_name .. ".test",
                ["Content-Length"] = #tostring(count),
              },
              body = count,
            })
            count = tonumber(res:read_body())
          end

          assert.equal(10, count)
        end)
      end)

      describe("sandbox access", function()
        it("can access cache", function()
          local res = assert(client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Host"] = "eleven." .. plugin_name .. ".test",
            },
          })
          local body = assert.res_status(200, res)
          assert.is_not_nil(body)
          assert.equal("val", body)
        end)

        it("cannot access gateway information through the cache", function()
          local res = assert(client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Host"] = "twelve." .. plugin_name .. ".test",
            },
          })
          local body = assert.res_status(200, res)
          assert.is_not_nil(body)
          assert.equal("nil", body)
        end)

        it("can access kong.configuration fields", function()
          local res = assert(client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Host"] = "thirteen." .. plugin_name .. ".test",
            },
          })
          local body = assert.res_status(200, res)
          assert.is_not_nil(body)
          assert.equal("bundled", body)
        end)

        it("redacts sensitive configuration fields", function()
          local res = assert(client:send {
            method = "GET",
            path = "/status/200",
            headers = {
              ["Host"] = "fourteen." .. plugin_name .. ".test",
            },
          })
          local body = assert.res_status(200, res)
          assert.is_not_nil(body)
          assert.match("%*+", body)
        end)
      end)

      describe("issues", function()
        it("does not crash even when query is cleared, #9246", function()
          local res = client:get("/status/200?a=b", {
            headers = {
              ["Host"] = "ten." .. plugin_name .. ".test"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same({}, json.uri_args)
        end)
      end)
    end)
  end
end
