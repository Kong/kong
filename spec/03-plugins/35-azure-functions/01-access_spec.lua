local helpers = require "spec.helpers"
local meta = require "kong.meta"


local server_tokens = meta._SERVER_TOKENS


for _, strategy in helpers.each_strategy() do
  describe("Plugin: Azure Functions (access) [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)

      local route2 = bp.routes:insert {
        hosts      = { "azure2.com" },
        protocols  = { "http", "https" },
        service    = bp.services:insert({
          protocol = "http",
          host     = "to.be.overridden",
          port     = 80,
        })
      }

      -- this plugin definition results in an upstream url to
      -- http://httpbin.org/anything
      -- which will echo the request for inspection
      bp.plugins:insert {
        name     = "azure-functions",
        route    = { id = route2.id },
        config   = {
          https           = true,
          appname         = "httpbin",
          hostdomain      = "org",
          routeprefix     = "anything",
          functionname    = "test-func-name",
          apikey          = "anything_but_an_API_key",
          clientid        = "and_no_clientid",
        },
      }

      assert(helpers.start_kong{
        database = strategy,
        plugins  = "azure-functions",
      })

    end) -- setup

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function ()
      proxy_client:close()
    end)

    teardown(function()
      helpers.stop_kong()
    end)


    it("passes request query parameters", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        query   = { hello = "world" },
        headers = {
          ["Host"] = "azure2.com"
        }
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.same({ hello ="world" }, json.args)
    end)

    it("passes request body", function()
      local body = "I'll be back"
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        body    = body,
        query   = { hello = "world" },
        headers = {
          ["Host"] = "azure2.com"
        }
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.same(body, json.data)
    end)

    it("passes the path parameters", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/and/then/some",
        headers = {
          ["Host"] = "azure2.com"
        }
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.matches("httpbin.org/anything/test%-func%-name/and/then/some", json.url)
    end)

    it("passes the method", function()
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/",
        headers = {
          ["Host"] = "azure2.com"
        }
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.same("POST", json.method)
    end)

    it("passes the headers", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/and/then/some",
        headers = {
          ["Host"] = "azure2.com",
          ["Just-A-Header"] = "just a value",
        }
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.same("just a value", json.headers["Just-A-Header"])
    end)

    it("injects the apikey and clientid", function()
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/",
        headers = {
          ["Host"] = "azure2.com"
        }
      })

      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      --assert.same({}, json.headers)
      assert.same("anything_but_an_API_key", json.headers["X-Functions-Key"])
      assert.same("and_no_clientid", json.headers["X-Functions-Clientid"])
    end)

    it("returns server tokens with Via header", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        query   = { hello = "world" },
        headers = {
          ["Host"] = "azure2.com"
        }
      })

      assert.equal(server_tokens, res.headers["Via"])
    end)

    it("returns Content-Length header", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        query   = { hello = "world" },
        headers = {
          ["Host"] = "azure2.com"
        }
      })

      assert(tonumber(res.headers["Content-Length"]) > 100)
    end)

  end) -- describe
end
