local helpers = require "spec.helpers"
local cjson   = require "cjson"
local pl_file = require "pl.file"
local meta    = require "kong.meta"


local server_tokens = meta._SERVER_TOKENS


describe("forward-proxy access", function()
  local client

  setup(function()
    local api1 = assert(helpers.dao.apis:insert {
      name         = "api-1",
      hosts        = { "api-1.com" },
      upstream_url = "http://example.com",
    })

    local api2 = assert(helpers.dao.apis:insert {
      name         = "api-2",
      hosts        = { "api-2.com" },
      upstream_url = "http://dne.com",
    })

    assert(helpers.dao.plugins:insert {
      name   = "forward-proxy",
      api_id = api1.id,
      config = {
        proxy_host = helpers.mock_upstream_host,
        proxy_port = helpers.mock_upstream_port,
      },
    })

    assert(helpers.dao.plugins:insert {
      name   = "forward-proxy",
      api_id = api2.id,
      config = {
        proxy_host = helpers.mock_upstream_host,
        proxy_port = helpers.mock_upstream_port - 1,
      },
    })

    assert(helpers.start_kong({
      plugins    = "forward-proxy",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    client = helpers.proxy_client()
  end)

  teardown(function()
    if client then
      client:close()
    end

    helpers.stop_kong()
  end)

  it("redirects a request", function()
    local res = assert(client:send {
      method  = "GET",
      path    = "/get",
      headers = {
        host = "api-1.com",
      },
    })


    assert.res_status(200, res)
  end)

  it("writes an absolute request URI to the proxy", function()
    local res = assert(client:send {
      method  = "GET",
      path    = "/get",
      headers = {
        host = "api-1.com",
      },
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.same("GET http://example.com/get HTTP/1.1",
                json.vars.request, nil, true)
  end)

  it("sends the lua-resty-http UA by default", function()
    local res = assert(client:send {
      method  = "GET",
      path    = "/get",
      headers = {
        host = "api-1.com",
      },
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.matches("lua-resty-http", json.headers["user-agent"], nil, true)
  end)

  it("forwards query params and request body data", function()
    local res = assert(client:send {
      method  = "POST",
      path    = "/post?baz=bat",
      headers = {
        host = "api-1.com",
        ["Content-Type"] = "application/json",
      },
      body = {
        foo = "bar"
      },
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.same(json.uri_args, { baz = "bat" })
    assert.same(json.post_data.params, { foo = "bar" })
  end)

  it("errors on connection failure", function()
    local res = assert(client:send {
      method  = "GET",
      path    = "/get",
      headers = {
        host = "api-2.com",
      },
    })

    assert.res_status(500, res)
    local err_log = pl_file.read(helpers.test_conf.nginx_err_logs)
    assert.matches("failed to connect to proxy: ", err_log, nil, true)
  end)

  describe("displays Kong core headers:", function()
    for _, s in ipairs({ "Proxy", "Upstream" }) do
      local name = string.format("X-Kong-%s-Latency", s)

      it(name, function()
        local res = assert(client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host = "api-1.com",
          },
        })

        assert.res_status(200, res)
        assert.matches("^%d+$", res.headers[name])
      end)
    end
  end)

  it("returns server tokens with Via header", function()
    local res = assert(client:send {
      method  = "GET",
      path    = "/get",
      headers = {
        host = "api-1.com",
      },
    })

    assert.equal(server_tokens, res.headers["Via"])
  end)

end)
