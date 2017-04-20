local helpers = require "spec.helpers"
local constants = require "kong.constants"


local default_server_header = _KONG._NAME .. "/" .. _KONG._VERSION


local function start(config)
  return function()
    helpers.dao.apis:insert {
      name = "api-1",
      upstream_url = "http://localhost:9999/headers-inspect",
      hosts = {
        "headers-inspect.com",
      }
    }

    config = config or {}
    config.nginx_conf = "spec/fixtures/custom_nginx.template"

    assert(helpers.start_kong(config))
  end
end


describe("Server Tokens", function()
  local client

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  describe("(with default configration values)", function()

    setup(start {
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })

    teardown(helpers.stop_kong)

    it("should return Kong 'Via' header but not change the 'Server' header when request was proxied", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "headers-inspect.com",
        }
      })

      assert.res_status(200, res)
      assert.not_equal(default_server_header, res.headers["server"])
      assert.equal(default_server_header, res.headers["via"])
    end)

    it("should return Kong 'Server' header but not the Kong 'Via' header when no API matched (no proxy)", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "404.com",
        }
      })

      assert.res_status(404, res)
      assert.equal(default_server_header, res.headers["server"])
      assert.is_nil(res.headers["via"])
    end)

  end)

  describe("(with server_tokens = on)", function()

    setup(start {
      nginx_conf    = "spec/fixtures/custom_nginx.template",
      server_tokens = "on",
    })

    teardown(helpers.stop_kong)

    it("should return Kong 'Via' header but not change the 'Server' header when request was proxied", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "headers-inspect.com",
        }
      })

      assert.res_status(200, res)
      assert.not_equal(default_server_header, res.headers["server"])
      assert.equal(default_server_header, res.headers["via"])
    end)

    it("should return Kong 'Server' header but not the Kong 'Via' header when no API matched (no proxy)", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "404.com",
        }
      })

      assert.res_status(404, res)
      assert.equal(default_server_header, res.headers["server"])
      assert.is_nil(res.headers["via"])
    end)

  end)

  describe("(with server_tokens = off)", function()

    setup(start {
      nginx_conf    = "spec/fixtures/custom_nginx.template",
      server_tokens = "off",
    })

    teardown(helpers.stop_kong)

    it("should not return Kong 'Via' header but it should forward the 'Server' header when request was proxied", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "headers-inspect.com",
        }
      })

      assert.res_status(200, res)
      assert.response(res).has.header "server"
      assert.response(res).has_not.header "via"
      assert.not_equal(default_server_header, res.headers["server"])
    end)

    it("should not return Kong 'Server' or 'Via' headers when no API matched (no proxy)", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "404.com",
        }
      })

      assert.res_status(404, res)
      assert.is_nil(res.headers["server"])
      assert.is_nil(res.headers["via"])
    end)

  end)
end)


describe("Latency Tokens", function()
  local client

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  describe("(with default configration values)", function()

    setup(start {
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })

    teardown(helpers.stop_kong)

    it("should be returned when request was proxied", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "headers-inspect.com",
        }
      })

      assert.res_status(200, res)
      assert.is_not_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
      assert.is_not_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
    end)

    it("should not be returned when no API matched (no proxy)", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "404.com",
        }
      })

      assert.res_status(404, res)
      assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
      assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
    end)

  end)

  describe("(with latency_tokens = on)", function()

    setup(start {
      nginx_conf = "spec/fixtures/custom_nginx.template",
      latency_tokens = "on",
    })

    teardown(helpers.stop_kong)

    it("should be returned when request was proxied", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "headers-inspect.com"
        }
      })

      assert.res_status(200, res)
      assert.is_not_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
      assert.is_not_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
    end)

    it("should not be returned when no API matched (no proxy)", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "404.com",
        }
      })

      assert.res_status(404, res)
      assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
      assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
    end)

  end)

  describe("(with latency_tokens = off)", function()

    setup(start {
      nginx_conf     = "spec/fixtures/custom_nginx.template",
      latency_tokens = "off",
    })

    teardown(function()
      helpers.stop_kong()
    end)

    it("should not be returned when request was proxied", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "headers-inspect.com",
        }
      })

      assert.res_status(200, res)
      assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
      assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
    end)

    it("should not be returned when no API matched (no proxy)", function()
      local res = assert(client:send {
        method  = "GET",
        path    = "/get",
        headers = {
          host  = "404.com",
        }
      })

      assert.res_status(404, res)
      assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
      assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
    end)

  end)
end)
