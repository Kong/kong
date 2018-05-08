local helpers = require "spec.helpers"
local cjson = require "cjson"
local meta = require "kong.meta"
local utils = require "kong.tools.utils"

describe("Plugin: workspace scope test key-auth (access)", function()
  local admin_client, proxy_client, api1, ws_foo, plugin1
  setup(function()
    helpers.dao:drop_schema()
    helpers.dao:run_migrations()

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    admin_client = helpers.admin_client()
    proxy_client = helpers.proxy_client()

    local res = assert(admin_client:send {
      method = "POST",
      path   = "/workspaces",
      body   = {
        name = "foo",
      },
      headers = {
        ["Content-Type"] = "application/json",
      }
    })
    assert.res_status(201, res)
    ws_foo = assert.response(res).has.jsonbody()

    local res = assert(admin_client:send {
      method = "POST",
      path   = "/workspaces",
      body   = {
        name = "bar",
      },
      headers = {
        ["Content-Type"] = "application/json",
      }
    })
    assert.res_status(201, res)
    ws_bar = assert.response(res).has.jsonbody()

    local res = assert(admin_client:send {
      method = "POST",
      path   = "/apis",
      body   = {
        name = "test",
        upstream_url = "http://httpbin.org",
        hosts = "api1.com"
      },
      headers = {
        ["Content-Type"] = "application/json",
      }
    })
    assert.res_status(201, res)
    api1 = assert.response(res).has.jsonbody()


    local res = assert(admin_client:send {
      method = "POST",
      path   = "/apis/" .. api1.name .. "/plugins" ,
      body   = {
        name = "key-auth",
      },
      headers = {
        ["Content-Type"] = "application/json",
      }
    })
    assert.res_status(201, res)
    plugin1 = assert.response(res).has.jsonbody()

    local res = assert(admin_client:send {
      method = "POST",
      path   = "/consumers" ,
      body   = {
        username = "bob",
      },
      headers = {
        ["Content-Type"] = "application/json",
      }
    })
    assert.res_status(201, res)
    local consumer1 = assert.response(res).has.jsonbody()

    local res = assert(admin_client:send {
      method = "POST",
      path   = "/consumers/" .. consumer1.username .. "/key-auth"   ,
      body   = {
        key = "kong",
      },
      headers = {
        ["Content-Type"] = "application/json",
      }
    })
    assert.res_status(201, res)
    assert.response(res).has.jsonbody()
  end)
  teardown(function()
    if admin_client then admin_client:close() end
    if proxy_client then proxy_client:close() end
    helpers.stop_kong()
  end)

  describe("test sharing api1 with foo", function()
    it("withoud sharing", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/anything",
        headers = {
          ["Host"] = "api1.com",
          ["apikey"] = "kong",
        }
      })
      assert.res_status(200, res)
    end)
    it("share api with foo", function()
      local res = assert(admin_client:send {
        method = "POST",
        path   = "/workspaces/foo/entities",
        body   = {
          entities = api1.id,
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      assert.res_status(201, res)

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/anything",
        headers = {
          ["Host"] = "api1.com",
          ["apikey"] = "kong",
        }
      })
      assert.res_status(200, res)
    end)
    it("add request-transformer on foo side", function()
      local res = assert(admin_client:send {
        method = "POST",
        path   = "/foo/apis/" .. api1.name .. "/plugins" ,
        body   = {
          name = "request-transformer-advanced",
          config = {
            add = {
              headers = "X-TEST:ok"
            }
          }
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      })
      assert.res_status(201, res)

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/anything",
        headers = {
          ["Host"] = "api1.com",
          ["apikey"] = "kong",
        }
      })
      assert.res_status(200, res)
      local body = assert.response(res).has.jsonbody()
      assert("ok", body.headers["X-Test"])
    end)
  end)
end)
