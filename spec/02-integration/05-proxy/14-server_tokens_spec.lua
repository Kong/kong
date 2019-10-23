local meta = require "kong.meta"
local helpers = require "spec.helpers"
local constants = require "kong.constants"
local cjson = require "cjson"
local utils   = require "kong.tools.utils"


local default_server_header = meta._SERVER_TOKENS


for _, strategy in helpers.each_strategy() do
describe("headers [#" .. strategy .. "]", function()

  local function stop()
    helpers.stop_kong()
  end

  describe("Server/Via", function()
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

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }, {
        "error-generator",
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

    describe("(with default configration values)", function()

      lazy_setup(start())

      lazy_teardown(stop)

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

      lazy_teardown(stop)

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

      lazy_teardown(stop)

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

      lazy_teardown(stop)

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

      lazy_teardown(stop)

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
    local bp
    local db

    local function start(config)
      return function()
        bp.routes:insert {
          hosts = { "headers-inspect.com" },
        }

        local service = bp.services:insert({
          protocol = helpers.mock_upstream_protocol,
          host     = helpers.mock_upstream_host,
          port     = 1, -- wrong port
        })

        bp.routes:insert({
          service = service,
          hosts = { "502.test" }
        })

        bp.routes:insert {
          hosts = { "error-rewrite.test" },
        }

        local access_error_route = bp.routes:insert {
          hosts = { "error-access.test" },
        }

        bp.plugins:insert {
          name = "error-generator",
          route = { id = access_error_route.id },
          config = {
            access = true,
          },
        }

        local header_filter_error_route = bp.routes:insert {
          hosts = { "error-header-filter.test" },
        }

        bp.plugins:insert {
          name = "error-generator",
          route = { id = header_filter_error_route.id },
          config = {
            header_filter = true,
          },
        }

        local request_termination_route = bp.routes:insert({
          service = service,
          hosts = { "request-termination.test" }
        })

        bp.plugins:insert {
          name = "request-termination",
          route = { id = request_termination_route.id },
        }

        config = config or {}
        config.database   = strategy
        config.nginx_conf = "spec/fixtures/custom_nginx.template"

        assert(helpers.start_kong(config))
      end
    end

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }, {
        "error-generator",
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

    describe("(with default configration values)", function()

      lazy_setup(start())
      lazy_teardown(stop)

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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
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
        assert.is_not_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)

      it("should not be returned when request is short-circuited", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "request-termination.test",
          }
        })

        assert.res_status(503, res)
        assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
        assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
        assert.is_not_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)

      it("should be returned when response status code is included in error_page directive (error_page not executing)", function()
        for _, code in ipairs({ 400, 404, 408, 411, 412, 413, 414, 417, 494, 500, 502, 503, 504 }) do
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/" .. code,
            headers = {
              host  = "headers-inspect.com",
            }
          })

          assert.res_status(code, res)
          assert.is_not_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
          assert.is_not_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
          assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
        end
      end)

      it("should be returned with 502 errors (error_page executing)", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "502.test",
          }
        })

        assert.res_status(502, res)
        assert.is_not_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
        assert.is_not_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)

      -- Too painfull to get this to work with dbless (need to start new Kong process etc.)
      if strategy ~= "off" then
        it("should not be returned when plugin errors on rewrite phase", function()
          local admin_client = helpers.admin_client()
          local uuid = utils.uuid()
          local res = assert(admin_client:send {
            method = "PUT",
            path = "/plugins/" .. uuid,
            body = {
              name = "error-generator",
              config = {
                rewrite = true,
              }
            },
            headers = {["Content-Type"] = "application/json"}
          })
          assert.res_status(200, res)
          admin_client:close()

          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/get",
            headers = {
              host  = "error-rewrite.test",
            }
          })

          db.plugins:delete({ id = uuid })

          assert.res_status(500, res)
          assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
          assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
          assert.is_not_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
        end)
      end

      it("should not be returned when plugin errors on access phase", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "error-access.test",
          }
        })

        assert.res_status(500, res)
        assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
        assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
        assert.is_not_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)


      -- TODO: currently we don't handle errors from plugins on header_filter or body_filter.
      pending("should be returned even when plugin errors on header filter phase", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "error-header-filter.test",
          }
        })

        assert.res_status(500, res)
        assert.is_not_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
        assert.is_not_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)

    end)

    describe("(with headers = latency_tokens)", function()

      lazy_setup(start {
        headers = "latency_tokens",
      })

      lazy_teardown(stop)

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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
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
        assert.is_not_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)

    end)

    describe("(with headers = X-Kong-Upstream-Latency)", function()

      lazy_setup(start {
        headers = "X-Kong-Upstream-Latency",
      })

      lazy_teardown(stop)

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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)

    end)

    describe("(with headers = X-Kong-Proxy-Latency)", function()

      lazy_setup(start {
        headers = "X-Kong-Proxy-Latency",
      })

      lazy_teardown(stop)

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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)

    end)

    describe("(with headers = X-Kong-Response-Latency)", function()

      lazy_setup(start {
        headers = "X-Kong-Response-Latency",
      })

      lazy_teardown(stop)

      it("should not return 'X-Kong-Proxy-Latency', 'X-Kong-Upstream-Latency' or 'X-Kong-Response-Latency' headers when request was proxied", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "headers-inspect.com"
          }
        })

        assert.res_status(200, res)
        assert.is_nil(res.headers[constants.HEADERS.UPSTREAM_LATENCY])
        assert.is_nil(res.headers[constants.HEADERS.PROXY_LATENCY])
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)

      it("should return 'X-Kong-Response-Latency' when no API matched (no proxy)", function()
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
        assert.is_not_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)

    end)

    describe("(with no latency_tokens in headers)", function()

      lazy_setup(start {
        headers = "off",
      })

      lazy_teardown(stop)

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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)

    end)

    describe("(with headers='server_tokens, X-Kong-Proxy-Latency')", function()

      lazy_setup(start{
        headers = "server_tokens, X-Kong-Proxy-Latency",
      })

      lazy_teardown(stop)

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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
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

      lazy_teardown(stop)

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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
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

      lazy_teardown(stop)

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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
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
        assert.is_nil(res.headers[constants.HEADERS.RESPONSE_LATENCY])
      end)
    end)
  end)

  describe("X-Kong-Admin-Latency", function()
    local admin_client

    local function start(config)
      return function()
        config = config or {}
        config.database   = strategy
        config.nginx_conf = "spec/fixtures/custom_nginx.template"

        assert(helpers.start_kong(config))
      end
    end

    before_each(function()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if admin_client then
        admin_client:close()
      end
    end)

    describe("(with default configration values)", function()
      lazy_setup(start())
      lazy_teardown(stop)

      it("should be returned when admin api is requested", function()
        local res = assert(admin_client:get("/"))
        assert.res_status(200, res)
        assert.is_not_nil(res.headers[constants.HEADERS.ADMIN_LATENCY])
      end)
    end)

    describe("(with headers = latency_tokens)", function()
      lazy_setup(start {
        headers = "latency_tokens",
      })
      lazy_teardown(stop)

      it("should be returned when admin api is requested", function()
        local res = assert(admin_client:get("/"))
        assert.res_status(200, res)
        assert.is_not_nil(res.headers[constants.HEADERS.ADMIN_LATENCY])
      end)
    end)

    describe("(with headers = X-Kong-Admin-Latency)", function()
      lazy_setup(start {
        headers = "latency_tokens",
      })
      lazy_teardown(stop)

      it("should be returned when admin api is requested", function()
        local res = assert(admin_client:get("/"))
        assert.res_status(200, res)
        assert.is_not_nil(res.headers[constants.HEADERS.ADMIN_LATENCY])
      end)
    end)

    describe("(with headers = off)", function()
      lazy_setup(start {
        headers = "off",
      })
      lazy_teardown(stop)

      it("should not be returned when admin api is requested", function()
        local res = assert(admin_client:get("/"))
        assert.res_status(200, res)
        assert.is_nil(res.headers[constants.HEADERS.ADMIN_LATENCY])
      end)
    end)
  end)
end)
end
