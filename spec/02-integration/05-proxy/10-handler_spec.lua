local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("OpenResty handlers", function()
  local api_client, proxy_client
  setup(function()
    assert(helpers.dao.apis:insert {
      name = "rewrite-api",
      uris = { "/mockbin" },
      strip_uri = true,
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.start_kong({
      custom_plugins = "rewrite",
      lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua"
    }))

    api_client = helpers.admin_client()
    proxy_client = helpers.proxy_client(2000)

    local res = assert(api_client:send {
      method = "POST",
      path = "/plugins/",
      headers = {
        ["Content-Type"] = "application/json"
      },
      body = {
        name = "rewrite"
      }
    })
    assert.res_status(201, res)
  end)

  teardown(function()
    if api_client then api_client:close() end
    if proxy_client then proxy_client:close() end
    helpers.stop_kong()
  end)

  describe("rewrite", function()
    it("rewrites to a matching API", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/inexistent?rewrite_to=%2Fmockbin",
      })
      assert.response(res).has.status(200)
    end)
    it("rewrites to an unmatching API", function()
      local res = assert(proxy_client:send {
        method = "GET",
        path = "/inexistent?rewrite_to=%2Fhelloworld",
      })
      assert.response(res).has.status(404)
    end)
  end)
end)
