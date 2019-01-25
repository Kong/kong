local meta = require "kong.meta"
local helpers = require "spec.helpers"
local constants = require "kong.constants"
local cjson = require "cjson"


local default_server_header = meta._SERVER_TOKENS


for _, strategy in helpers.each_strategy() do
describe("headers [#" .. strategy .. "]", function()

  describe("Server/Via", function()
    local proxy_client
    local bp, dao

    local function start(config)
      return function()
        helpers.with_current_ws(nil, function()
        bp.routes:insert {
          hosts = { "headers-inspect.com" },
        }

        config = config or {}
        config.database   = strategy
        config.nginx_conf = "spec/fixtures/custom_nginx.template"

        assert(helpers.start_kong(config))
        end, dao)
      end
    end

<<<<<<< HEAD
    setup(function()
      bp, _, dao = helpers.get_db_utils(strategy)
||||||| merged common ancestors
    setup(function()
      bp = helpers.get_db_utils(strategy)
=======
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      })
>>>>>>> 0.15.0
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

      lazy_setup(start())

      lazy_teardown(helpers.stop_kong)

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

      lazy_setup(start {
        headers = "Via",
      })

      lazy_teardown(helpers.stop_kong)

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

      lazy_setup(start {
        headers = "Server",
      })

      lazy_teardown(helpers.stop_kong)

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

      lazy_setup(start {
        headers = "server_tokens",
      })

      lazy_teardown(helpers.stop_kong)

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

      lazy_setup(start {
        headers = "off",
      })

      lazy_teardown(helpers.stop_kong)

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


  describe("X-Kong-Proxy-Latency/X-Kong-Upstream-Latency", function()
    local proxy_client
    local bp, dao -- luacheck: ignore

    local function start(config)
      return function()
        helpers.with_current_ws(nil, function()
        bp.routes:insert {
          hosts = { "headers-inspect.com" },
        }
        end, dao)

        config = config or {}
        config.database   = strategy
        config.nginx_conf = "spec/fixtures/custom_nginx.template"

        assert(helpers.start_kong(config))
      end
    end

<<<<<<< HEAD
    setup(function()
      bp, _, dao = helpers.get_db_utils(strategy)
||||||| merged common ancestors
    setup(function()
      bp = helpers.get_db_utils(strategy)
=======
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      })
>>>>>>> 0.15.0
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

      lazy_setup(start())

      lazy_teardown(helpers.stop_kong)

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

      lazy_setup(start {
        headers = "latency_tokens",
      })

      lazy_teardown(helpers.stop_kong)

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

      lazy_setup(start {
        headers = "X-Kong-Upstream-Latency",
      })

      lazy_teardown(helpers.stop_kong)

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

      lazy_setup(start {
        headers = "X-Kong-Proxy-Latency",
      })

      lazy_teardown(helpers.stop_kong)

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

      lazy_setup(start {
        headers = "off",
      })

      lazy_teardown(function()
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

      lazy_setup(start{
        headers = "server_tokens, X-Kong-Proxy-Latency",
      })

      lazy_teardown(helpers.stop_kong)

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

      it("can be specified via configuration file", function()
        -- A regression test added with https://github.com/Kong/kong/pull/3419
        -- to ensure that the `headers` configuration value can be specified
        -- via the configuration file (vs. environment variables as the rest
        -- of this test suite uses).
        -- This regression occured because of the dumping of config values into
        -- .kong_env (and the lack of serialization for the `headers` table).
        assert(helpers.kong_exec("restart -c spec/fixtures/headers.conf"))

        local admin_client = helpers.admin_client()
        local res = assert(admin_client:send {
          method = "GET",
          path   = "/",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal("server_tokens", json.configuration.headers[1])
        assert.equal("X-Kong-Proxy-Latency", json.configuration.headers[2])
      end)
    end)

    describe("(with headers='server_tokens, off, X-Kong-Proxy-Latency')", function()

      lazy_setup(start{
        headers = "server_tokens, off, X-Kong-Proxy-Latency",
      })

      lazy_teardown(helpers.stop_kong)

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

  describe("case insensitiveness", function()
    local proxy_client
    local bp

    local function start(config)
      return function()
        bp.routes:insert {
          hosts = { "headers-inspect.com" },
        }

        config = config or {}
        config.database = strategy
        config.nginx_conf = "spec/fixtures/custom_nginx.template"

        assert(helpers.start_kong(config))
      end
    end

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      })
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

      lazy_setup(start{
        headers = "serVer_TokEns, x-kOng-pRoXy-lAtency"
      })

      lazy_teardown(helpers.stop_kong)

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
end)
end
