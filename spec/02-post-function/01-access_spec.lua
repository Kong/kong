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

describe("Plugin: post-function (access)", function()
  local client, admin_client

  setup(function()
    helpers.dao:run_migrations()

    local api1 = assert(helpers.dao.apis:insert {
      name         = "api-1",
      hosts        = { "api1.post-function.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(helpers.dao.plugins:insert {
      name   = "post-function",
      api_id = api1.id,
      config = {
        functions = { mock_fn_one }
      },
    })

    local api2 = assert(helpers.dao.apis:insert {
      name         = "api-2",
      hosts        = { "api2.post-function.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(helpers.dao.plugins:insert {
      name   = "post-function",
        api_id = api2.id,
        config = {
          functions = { mock_fn_two }
        },
    })

    local api3 = assert(helpers.dao.apis:insert {
      name         = "api-3",
      hosts        = { "api3.post-function.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(helpers.dao.plugins:insert {
      name   = "post-function",
        api_id = api3.id,
        config = {
          functions = { mock_fn_three }
        },
    })

    local api4 = assert(helpers.dao.apis:insert {
      name         = "api-4",
      hosts        = { "api4.post-function.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(helpers.dao.plugins:insert {
      name   = "post-function",
      api_id = api4.id,
      config = {
        functions = { mock_fn_four, mock_fn_five }
      },
    })


    assert(helpers.start_kong({
      custom_plugins = "post-function",
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
          ["Host"] = "api1.post-function.com"
        }
      })

      assert.res_status(503, res)
    end)

    it("using ngx.status and exit", function()
      local res = assert(client:send {
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "api2.post-function.com"
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
          ["Host"] = "api3.post-function.com"
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
          ["Host"] = "api4.post-function.com"
        }
      })
      local body = assert.res_status(400, res)
      assert.same("Bad request", body)
    end)
  end)
end)
