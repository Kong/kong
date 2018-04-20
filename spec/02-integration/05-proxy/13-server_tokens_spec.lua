local helpers = require "spec.helpers"
local constants = require "kong.constants"


local default_server_header = _KONG._NAME .. "/" .. _KONG._VERSION


for _, strategy in helpers.each_strategy() do
  describe("Headers [#" .. strategy .. "]", function()
    local proxy_client
    local bp

    local function start(config)
      return function()
        bp.routes:insert {
          hosts = { "headers-inspect.com" },
        }

        config = config or {}
        config.database   = strategy
        config.nginx_conf = "spec/fixtures/custom_nginx.template"

        assert(helpers.start_kong(config))
      end
    end

    setup(function()
      bp = helpers.get_db_utils(strategy)
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    describe("are case insensitive", function()

      setup(start{
        headers = "serVer_TokEns, x-kOng-pRoXy-lAtency"
      })

      teardown(helpers.stop_kong)

      it("should return Kong 'Via' and 'X-Kong-Proxy-Latency' header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "headers-inspect.com",
          }
        })

        assert.res_status(200, res)
        assert.not_equal(default_server_header, res.headers["server"])
        assert.equal(default_server_header, res.headers["via"])
        assert.is_not_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
      end)

      it("should return Kong 'Server' header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "404.com",
          }
        })

        assert.res_status(404, res)
        assert.equal(default_server_header, res.headers["server"])
        assert.is_nil(res.headers["via"])
        assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
      end)

    end)

  end)

  -- original
  describe("Server Tokens [#" .. strategy .. "]", function()
    local proxy_client
    local bp

    local function start(config)
      return function()
        bp.routes:insert {
          hosts = { "headers-inspect.com" },
        }

        config = config or {}
        config.database   = strategy
        config.nginx_conf = "spec/fixtures/custom_nginx.template"

        assert(helpers.start_kong(config))
      end
    end

    setup(function()
      bp = helpers.get_db_utils(strategy)
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    describe("(with default configration values)", function()

      setup(start())

      teardown(helpers.stop_kong)

      it("should return Kong 'Via' header but not change the 'Server' header when request was proxied", function()
        local res = assert(proxy_client:send {
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
        local res = assert(proxy_client:send {
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

    describe("(with headers = Via)", function()

      setup(start{
        headers = "Via",
      })

      teardown(helpers.stop_kong)

      it("should return Kong 'Via' header but not touch 'Server' header when request was proxied", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "headers-inspect.com",
          }
        })

        assert.res_status(200, res)
        assert.equal(default_server_header, res.headers["via"])
        assert.not_equal(default_server_header, res.headers["server"])
      end)

      it("should not return Kong 'Via' header or Kong 'Via' header when no API matched (no proxy)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "404.com",
          }
        })

        assert.res_status(404, res)
        assert.is_nil(res.headers["via"])
        assert.is_nil(res.headers["server"])
      end)

    end)

    describe("(with headers = Server)", function()

      setup(start{
        headers = "Server",
      })

      teardown(helpers.stop_kong)

      it("should not return Kong 'Via' header but not change the 'Server' header when request was proxied", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "headers-inspect.com",
          }
        })

        assert.res_status(200, res)
        assert.not_equal(default_server_header, res.headers["server"])
        assert.is_nil(res.headers["via"])
      end)

      it("should return Kong 'Server' header but not the Kong 'Via' header when no API matched (no proxy)", function()
        local res = assert(proxy_client:send {
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

    describe("(with headers = server_tokens)", function()

      setup(start {
        headers = "server_tokens",
      })

      teardown(helpers.stop_kong)

      it("should return Kong 'Via' header but not change the 'Server' header when request was proxied", function()
        local res = assert(proxy_client:send {
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
        local res = assert(proxy_client:send {
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

    describe("(with no server_tokens in headers)", function()

      setup(start {
        headers = "off",
      })

      teardown(helpers.stop_kong)

      it("should not return Kong 'Via' header but it should forward the 'Server' header when request was proxied", function()
        local res = assert(proxy_client:send {
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
        local res = assert(proxy_client:send {
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
    local proxy_client
    local bp

    local function start(config)
      return function()
        bp.routes:insert {
          hosts = { "headers-inspect.com" },
        }

        config = config or {}
        config.database   = strategy
        config.nginx_conf = "spec/fixtures/custom_nginx.template"

        assert(helpers.start_kong(config))
      end
    end

    setup(function()
      bp = helpers.get_db_utils(strategy)
    end)


    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    describe("(with default configration values)", function()

      setup(start())

      teardown(helpers.stop_kong)

      it("should be returned when request was proxied", function()
        local res = assert(proxy_client:send {
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
        local res = assert(proxy_client:send {
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

    describe("(with headers = latency_tokens)", function()

      setup(start {
        headers = "latency_tokens",
      })

      teardown(helpers.stop_kong)

      it("should be returned when request was proxied", function()
        local res = assert(proxy_client:send {
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
        local res = assert(proxy_client:send {
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

    describe("(with headers = X-Kong-Upstream-Latency)", function()

      setup(start {
        headers = "X-Kong-Upstream-Latency",
      })

      teardown(helpers.stop_kong)

      it("should return 'X-Kong-Upstream-Latency' header but not 'X-Kong-Proxy-Latency' when request was proxied", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "headers-inspect.com"
          }
        })

        assert.res_status(200, res)
        assert.is_not_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
        assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
      end)

      it("should not return any latency header when no API matched (no proxy)", function()
        local res = assert(proxy_client:send {
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

    describe("(with headers = X-Kong-Proxy-Latency)", function()

      setup(start {
        headers = "X-Kong-Proxy-Latency",
      })

      teardown(helpers.stop_kong)

      it("should return 'X-Kong-Proxy-Latency' header but not 'X-Kong-Upstream-Latency' when request was proxied", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "headers-inspect.com"
          }
        })

        assert.res_status(200, res)
        assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
        assert.is_not_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
      end)

      it("should not return any latency header when no API matched (no proxy)", function()
        local res = assert(proxy_client:send {
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

    describe("(with no latency_tokens in headers)", function()

      setup(start {
        headers = "off",
      })

      teardown(function()
        helpers.stop_kong()
      end)

      it("should not be returned when request was proxied", function()
        local res = assert(proxy_client:send {
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
        local res = assert(proxy_client:send {
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

    describe("(with headers='server_tokens, X-Kong-Proxy-Latency')", function()

      setup(start{
        headers = "server_tokens, X-Kong-Proxy-Latency",
      })

      teardown(helpers.stop_kong)

      it("should return Kong 'Via' and 'X-Kong-Proxy-Latency' header but not change the 'Server' header when request was proxied", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "headers-inspect.com",
          }
        })

        assert.res_status(200, res)
        assert.not_equal(default_server_header, res.headers["server"])
        assert.equal(default_server_header, res.headers["via"])
        assert.is_not_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
      end)

      it("should return Kong 'Server' header but not the Kong 'Via' or 'X-Kong-Proxy-Latency' header when no API matched (no proxy)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "404.com",
          }
        })

        assert.res_status(404, res)
        assert.equal(default_server_header, res.headers["server"])
        assert.is_nil(res.headers["via"])
        assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
      end)

    end)

    describe("(with headers='server_tokens, off, X-Kong-Proxy-Latency')", function()

      setup(start{
        headers = "server_tokens, off, X-Kong-Proxy-Latency",
      })

      teardown(helpers.stop_kong)

      it("should return Kong 'Via' and 'X-Kong-Proxy-Latency' header as 'off' will not take effect", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "headers-inspect.com",
          }
        })

        assert.res_status(200, res)
        assert.not_equal(default_server_header, res.headers["server"])
        assert.equal(default_server_header, res.headers["via"])
        assert.is_not_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
      end)

      it("should return Kong 'Server' header as 'off' will not take effect", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "404.com",
          }
        })

        assert.res_status(404, res)
        assert.equal(default_server_header, res.headers["server"])
        assert.is_nil(res.headers["via"])
        assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
      end)

    end)
  end)
end
