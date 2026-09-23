local helpers   = require "spec.helpers"
local http_mock = require "spec.helpers.http_mock"
local cjson     = require "cjson"
local meta      = require "kong.meta"
local re_match  = ngx.re.match


local str_fmt   = string.format

local SERVER_TOKENS = meta._SERVER_TOKENS

for _, strategy in helpers.all_strategies() do
  describe("append Kong Gateway info to the 'Via' header [#" .. strategy .. "]", function()
    local mock, declarative_config, proxy_client, proxy_client_h2, proxy_client_grpc, proxy_client_grpcs

    lazy_setup(function()
      local mock_port = helpers.get_available_port()
      mock = http_mock.new(mock_port, {
        ["/via"] = {
          access = [=[
            ngx.req.set_header("X-Req-To", "http_mock")
          ]=],
          content = [=[
            local cjson = require "cjson"
            ngx.say(cjson.encode({ via = tostring(ngx.var.http_via) }))
          ]=],
          -- bug: https://github.com/Kong/kong/pull/12753
          header_filter = "", header = [=[
            ngx.header["Server"] = 'http-mock'
            ngx.header["Via"] = '2 nginx, HTTP/1.1 http_mock'
            ngx.header["Content-type"] = 'application/json'
          ]=],
        },
      }, {
        prefix = "servroot_mock",
        req = true,
        resp = false,
      })
      assert(mock:start())

      local bp = helpers.get_db_utils(
        strategy == "off" and "postgres" or strategy,
        {
          "routes",
          "services",
        }
      )

      local service1 = assert(bp.services:insert {
        name = "via_service",
        url = "http://127.0.0.1:" .. mock_port .. "/via",
      })

      assert(bp.routes:insert {
        name = "via_route",
        hosts = { "test.via" },
        paths = { "/get" },
        service = { id = service1.id },
      })

      local service2 = assert(bp.services:insert {
        name = "grpc_service",
        url = helpers.grpcbin_url,
      })

      assert(bp.routes:insert {
        name = "grpc_route",
        hosts = { "grpc" },
        paths = { "/" },
        service = { id = service2.id },
      })

      local service3 = assert(bp.services:insert {
        name = "grpcs_service",
        url = helpers.grpcbin_ssl_url,
      })

      assert(bp.routes:insert {
        name = "grpcs_route",
        hosts = { "grpcs" },
        paths = { "/" },
        service = { id = service3.id },
      })

      declarative_config = helpers.make_yaml_file(str_fmt([=[
        _format_version: '3.0'
        _transform: true
        services:
        - name: via_service
          url: "http://127.0.0.1:%s/via"
          routes:
          - name: via_route
            hosts:
            - test.via
            paths:
            - /get
        - name: grpc_service
          url: %s
          routes:
          - name: grpc_route
            protocols:
            - grpc
            hosts:
            - grpc
            paths:
            - /
        - name: grpcs_service
          url: %s
          routes:
          - name: grpcs_route
            protocols:
            - grpc
            hosts:
            - grpcs
            paths:
            - /
      ]=], mock_port, helpers.grpcbin_url, helpers.grpcbin_ssl_url))

      assert(helpers.start_kong({
        database = strategy,
        plugins = "bundled",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = strategy == "off" and declarative_config or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
        nginx_worker_processes = 1,
      }))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
      mock:stop()
    end)

    it("HTTP/1.1 in both the inbound and outbound directions", function()
      proxy_client = helpers.proxy_client()

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/get",
        headers = {
          ["Host"] = "test.via",
          ["Via"] = "1.1 dev",
        }
      })

      local body = assert.res_status(200, res)
      local json_body = cjson.decode(body)
      assert.are_same({ via = "1.1 dev, 1.1 " .. SERVER_TOKENS }, json_body)
      assert.are_same("2 nginx, HTTP/1.1 http_mock, 1.1 " .. SERVER_TOKENS, res.headers["Via"])
      assert.are_same("http-mock", res.headers["Server"])

      if proxy_client then
        proxy_client:close()
      end
    end)

    it("HTTP/2 in both the inbound and outbound directions", function()
      proxy_client_h2 = helpers.proxy_client_h2()

      local body, headers = assert(proxy_client_h2({
        headers = {
          [":method"] = "GET",
          [":scheme"] = "https",
          [":authority"] = "test.via",
          [":path"] = "/get",
          ["via"] = [['1.1 dev']],
        }
      }))

      assert.are_equal(200, tonumber(headers:get(":status")))
      local json_body = cjson.decode(body)
      assert.are_same({ via = "1.1 dev, 2 " .. SERVER_TOKENS }, json_body)
      assert.are_same("2 nginx, HTTP/1.1 http_mock, 1.1 " .. SERVER_TOKENS, headers:get("Via"))
      assert.are_same("http-mock", headers:get("Server"))
    end)

    it("gRPC without SSL in both the inbound and outbound directions", function()
      proxy_client_grpc = helpers.proxy_client_grpc()

      local ok, resp = assert(proxy_client_grpc({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-v"] = true,
          ["-authority"] = "grpc",
        }
      }))

      assert.truthy(ok)
      local server = re_match(resp, [=[Response headers received\:[\s\S]*\nserver\:\s(.*?)\n]=], "jo")
      assert.are_equal(SERVER_TOKENS, server[1])
      local via = re_match(resp, [=[Response headers received\:[\s\S]*\nvia\:\s(.*?)\n]=], "jo")
      assert.are_equal("2 " .. SERVER_TOKENS, via[1])
      local body = re_match(resp, [=[Response contents\:([\s\S]+?)\nResponse trailers received]=], "jo")
      local json_body = cjson.decode(body[1])
      assert.are_equal("hello world!", json_body.reply)
    end)

    it("gRPC with SSL in both the inbound and outbound directions", function()
      proxy_client_grpcs = helpers.proxy_client_grpcs()

      local ok, resp = assert(proxy_client_grpcs({
        service = "hello.HelloService.SayHello",
        body = {
          greeting = "world!"
        },
        opts = {
          ["-v"] = true,
          ["-authority"] = "grpcs",
        }
      }))

      assert.truthy(ok)
      local server = re_match(resp, [=[Response headers received\:[\s\S]*\nserver\:\s(.*?)\n]=], "jo")
      assert.are_equal(SERVER_TOKENS, server[1])
      local via = re_match(resp, [=[Response headers received\:[\s\S]*\nvia\:\s(.*?)\n]=], "jo")
      assert.are_equal("2 " .. SERVER_TOKENS, via[1])
      local body = re_match(resp, [=[Response contents\:([\s\S]+?)\nResponse trailers received]=], "jo")
      local json_body = cjson.decode(body[1])
      assert.are_equal("hello world!", json_body.reply)
    end)
  end)
end
