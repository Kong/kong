local helpers = require "spec.helpers"
local meta = require "kong.meta"

local http_mock = require "spec.helpers.http_mock"

local server_tokens = meta._SERVER_TOKENS


for _, strategy in helpers.each_strategy() do
  describe("Plugin: Azure Functions (access) [#" .. strategy .. "]", function()
    local mock
    local proxy_client
    local mock_http_server_port = helpers.get_available_port()

    mock = http_mock.new("127.0.0.1:" .. mock_http_server_port, {
      ["/"] = {
        access = [[
          local json = require "cjson"
          local method = ngx.req.get_method()
          local uri = ngx.var.request_uri
          local headers = ngx.req.get_headers(nil, true)
          local query_args = ngx.req.get_uri_args()
          ngx.req.read_body()
          local body
          -- collect body
          body = ngx.req.get_body_data()
          if not body then
            local file = ngx.req.get_body_file()
            if file then
              local f = io.open(file, "r")
              if f then
                body = f:read("*a")
                f:close()
              end
            end
          end
          ngx.say(json.encode({
            query_args = query_args,
            uri = uri,
            method = method,
            headers = headers,
            body = body,
            status = 200,
          }))
        ]]
      },
    })

    setup(function()
      local _, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local route2 = db.routes:insert {
        hosts      = { "azure2.com" },
        protocols  = { "http", "https" },
      }

      -- Mocking lua-resty-http's request_uri function
      db.plugins:insert {
        name = "pre-function",
        route = { id = route2.id },
        config = {
          access = {
            [[
              local http = require "resty.http"
              local json = require "cjson"
              local _request_uri = http.request_uri
              http.request_uri = function (self, uri, params)
                local scheme, host, port, _, _ = unpack(http:parse_uri(uri))
                local mock_server_port = ]] .. mock_http_server_port .. [[
                -- Replace the port with the mock server port
                local new_uri = string.format("%s://%s:%d", scheme, host, mock_server_port)
                ngx.log(ngx.ERR, "REPLACE URI WITH:" .. new_uri)
                return _request_uri(self, new_uri, params)
              end
            ]]
          }
        }
      }

      -- this plugin definition results in an upstream url to
      -- http://mockbin.org/request
      -- which will echo the request for inspection
      db.plugins:insert {
        name     = "azure-functions",
        route    = { id = route2.id },
        config   = {
          https           = false,
          appname         = "mockbin",
          hostdomain      = "org",
          routeprefix     = "request",
          functionname    = "test-func-name",
          apikey          = "anything_but_an_API_key",
          clientid        = "and_no_clientid",
        },
      }

      local fixtures = {
        dns_mock = helpers.dns_mock.new()
      }

      fixtures.dns_mock:A({
        name = "mockbin.org",
        address = "127.0.0.1",
      })

      assert(helpers.start_kong({
        database = strategy,
        untrusted_lua = "on",
        plugins  = "azure-functions,pre-function",
      }, nil, nil, fixtures))

      assert(mock:start())
    end) -- setup

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function ()
      proxy_client:close()
    end)

    teardown(function()
      helpers.stop_kong()
      assert(mock:stop())
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
      assert.same({ hello ="world" }, json.query_args)
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
      assert.same(body, json.body)
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
      assert.matches("/request/test%-func%-name/and/then/some", json.uri)
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
      assert.same("just a value", json.headers["just-a-header"])
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
      assert.same("anything_but_an_API_key", json.headers["x-functions-key"])
      assert.same("and_no_clientid", json.headers["x-functions-clientid"])
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
