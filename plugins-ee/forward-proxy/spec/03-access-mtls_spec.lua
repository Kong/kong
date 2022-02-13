-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers      = require "spec.helpers"
local ssl_fixtures = require "spec.fixtures.ssl"
local pl_path      = require "pl.path"


local fixtures = {
  dns_mock = helpers.dns_mock.new(),
  stream_mock = {
    forward_proxy = [[
    # This is a very naive forward proxy, which accepts a CONNECT over HTTP, and
    # then starts tunnelling the bytes blind (for end-to-end SSL).
    server {
      listen 16797;
      error_log logs/naive_forward_proxy.log debug;

      content_by_lua_block {
        local split = require("kong.tools.utils").split

        local req_sock = ngx.req.socket(true)
        req_sock:settimeouts(100, 1000, 1000)

        -- receive request line
        local req_line = req_sock:receive()
        ngx.log(ngx.DEBUG, "request line: ", req_line)

        local method, host_port, version = unpack(split(req_line, " "))
        if method ~= "CONNECT" then
          return ngx.exit(400)
        end

        local upstream_host, upstream_port = unpack(split(host_port, ":"))

        -- receive and discard any headers
        repeat
          local line = req_sock:receive("*l")
          ngx.log(ngx.DEBUG, "request header: ", line)
        until ngx.re.find(line, "^\\s*$", "jo")

        -- Connect to requested upstream
        local upstream_sock = ngx.socket.tcp()
        upstream_sock:settimeouts(100, 1000, 1000)
        local ok, err = upstream_sock:connect(upstream_host, upstream_port)
        if not ok then
          return ngx.exit(504)
        end

        -- Tell the client we are good to go
        ngx.print("HTTP/1.1 200 OK\n\n")
        ngx.flush()

        -- 10Kb in either direction should be plenty
        local max_bytes = 10 * 1024

        repeat
          local req_data = req_sock:receiveany(max_bytes)
          if req_data then
            ngx.log(ngx.DEBUG, "client RCV ", #req_data, " bytes")

            local bytes, err = upstream_sock:send(req_data)
            if bytes then
              ngx.log(ngx.DEBUG, "upstream SND ", bytes, " bytes")
            end
          end

          local res_data = upstream_sock:receiveany(max_bytes)
          if res_data then
            ngx.log(ngx.DEBUG, "upstream RCV ", #res_data, " bytes")

            local bytes, err = req_sock:send(res_data)
            if bytes then
              ngx.log(ngx.DEBUG, "client SND: ", bytes, " bytes")
            end
          end
        until not req_data and not res_data -- request socket should be closed

        req_sock:close()
        upstream_sock:close()
      }
    }
    ]],
  },
  http_mock = {
    upstream_mtls = [[
      server {
          server_name example.com;
          listen 16798 ssl;

          ssl_certificate        /kong/spec/fixtures/mtls_certs/example.com.crt;
          ssl_certificate_key    /kong/spec/fixtures/mtls_certs/example.com.key;
          ssl_client_certificate /kong/spec/fixtures/mtls_certs/ca.crt;
          ssl_verify_client      on;
          ssl_session_tickets    off;
          ssl_session_cache      off;
          keepalive_requests     0;

          location = / {
              echo 'it works';
          }
      }
    ]],
  },
}


fixtures.dns_mock:A {
  name = "example.com",
  address = "127.0.0.1",
}

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe("forward-proxy mTLS #" .. strategy, function()
    local proxy_client, admin_client
    local bp
    local service_mtls
    local certificate
    local route_mtls

    local strategy = strategy ~= "off" and strategy or nil
    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "certificates",
        "ca_certificates",
        "upstreams",
        "targets",
      }, {
        "forward-proxy",
      })

      service_mtls = assert(bp.services:insert({
        name = "protected-service-mtls",
        url = "https://127.0.0.1:16798/",
      }))

      certificate = assert(bp.certificates:insert({
        cert = ssl_fixtures.cert_client,
        key = ssl_fixtures.key_client,
      }))

      route_mtls = assert(bp.routes:insert({
        service = { id = service_mtls.id, },
        hosts = { "example.com", },
        paths = { "/mtls", },
      }))

      assert(bp.plugins:insert {
        route = { id = route_mtls.id },
        name   = "forward-proxy",
        config = {
          https_proxy_host = "127.0.0.1",
          https_proxy_port = 16797,
        },
      })

      assert(helpers.start_kong({
        database   = strategy,
        plugins = "forward-proxy",
        nginx_conf = "spec/fixtures/custom_nginx.template",

        -- this is unused, but required for the the template to include a stream {} block
        stream_listen = "0.0.0.0:5555",
      }, nil, true, fixtures))

      proxy_client = assert(helpers.proxy_ssl_client(200, "example.com"))
      admin_client = assert(helpers.admin_client())
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong()
    end)

    describe("mTLS authentication against upstream with Service object, via forward-proxy", function()
      describe("no client certificate supplied", function()
        it("accessing protected upstream", function()
          local res = assert(proxy_client:send {
            path    = "/mtls",
            headers = {
              ["Host"] = "example.com",
            }
          })

          local body = assert.res_status(400, res)
          assert.matches("400 No required SSL certificate was sent", body, nil, true)
        end)
      end)

      describe("#db client certificate supplied via service.client_certificate", function()
        lazy_setup(function()
          local res = assert(admin_client:patch("/services/" .. service_mtls.id, {
            body = {
              client_certificate = { id = certificate.id, },
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)
        end)

        it("accessing protected upstream", function()
          local res = assert(proxy_client:send {
            path    = "/mtls",
            headers = {
              ["Host"] = "example.com",
            }
          })

          local body = assert.res_status(200, res)
          assert.equals("it works", body)

          -- Ensure we actually went via the forward-proxy
          local forward_proxy_log = helpers.test_conf.prefix ..
                                    "/logs/naive_forward_proxy.log"

          helpers.wait_until(function()
            return pl_path.exists(forward_proxy_log) and
                   pl_path.getsize(forward_proxy_log) > 0
          end, 5)
        end)

        it("remove client_certificate removes access", function()
          local res = assert(admin_client:patch("/services/" .. service_mtls.id, {
            body = {
              client_certificate = ngx.null,
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          res = assert(proxy_client:send {
            path    = "/mtls",
            headers = {
              ["Host"] = "example.com",
            }
          })

          local body = assert.res_status(400, res)
          assert.matches("400 No required SSL certificate was sent", body, nil, true)
        end)
      end)
    end)
  end)
end
