local ssl_fixtures = require "spec.fixtures.ssl"
local helpers      = require "spec.helpers"
local cjson        = require "cjson"


local function get_cert(server_name)
  local _, _, stdout = assert(helpers.execute(
    string.format("echo 'GET /' | openssl s_client -connect 0.0.0.0:%d -servername %s",
                  helpers.get_proxy_port(true), server_name)
  ))

  return stdout
end

for _, strategy in helpers.each_strategy() do
  describe("SSL [#" .. strategy .. "]", function()
    local admin_client
    local proxy_client
    local https_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy)

      local service = bp.services:insert {
        name = "global-cert",
      }

      bp.routes:insert {
        protocols = { "https" },
        hosts     = { "global.com" },
        service   = service,
      }

      local service2 = bp.services:insert {
        name = "api-1",
      }

      bp.routes:insert {
        protocols = { "https" },
        hosts     = { "example.com", "ssl1.com" },
        service   = service2,
      }

      local service4 = bp.services:insert {
        name     = "api-3",
        protocol = helpers.mock_upstream_ssl_protocol,
        host     = helpers.mock_upstream_hostname,
        port     = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert {
        protocols     = { "https" },
        hosts         = { "ssl3.com" },
        service       = service4,
        preserve_host = true,
      }

      local service5 = bp.services:insert {
        name     = "api-4",
        protocol = helpers.mock_upstream_ssl_protocol,
        host     = helpers.mock_upstream_hostname,
        port     = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert {
        protocols     = { "https" },
        hosts         = { "no-sni.com" },
        service       = service5,
        preserve_host = false,
      }

      local service6 = bp.services:insert {
        name     = "api-5",
        protocol = helpers.mock_upstream_ssl_protocol,
        host     = "127.0.0.1",
        port     = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert {
        protocols     = { "https" },
        hosts         = { "nil-sni.com" },
        service       = service6,
        preserve_host = false,
      }

      assert(helpers.start_kong {
        database    = strategy,
        nginx_conf  = "spec/fixtures/custom_nginx.template",
        trusted_ips = "127.0.0.1",
      })

      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
      https_client = helpers.proxy_ssl_client()

      assert(admin_client:send {
        method  = "POST",
        path    = "/certificates",
        body    = {
          cert  = ssl_fixtures.cert,
          key   = ssl_fixtures.key,
          snis  = { "example.com", "ssl1.com" },
        },
        headers = { ["Content-Type"] = "application/json" },
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("global SSL", function()
      it("fallbacks on the default proxy SSL certificate when SNI is not provided by client", function()
        local res = assert(https_client:send {
          method  = "GET",
          path    = "/status/200",
          headers = {
            Host  = "global.com"
          }
        })
        assert.res_status(200, res)
      end)
    end)

    describe("handshake", function()
      it("sets the default fallback SSL certificate if no SNI match", function()
        local cert = get_cert("test.com")
        assert.cn("localhost", cert)
      end)

      it("sets the configured SSL certificate if SNI match", function()
        local cert = get_cert("ssl1.com")
        assert.cn("ssl-example.com", cert)

        cert = get_cert("example.com")
        assert.cn("ssl-example.com", cert)
      end)
    end)

    describe("SSL termination", function()
      it("blocks request without HTTPS if protocols = { http }", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            ["Host"] = "example.com",
          }
        })

        local body = assert.res_status(426, res)
        local json = cjson.decode(body)
        assert.same({ message = "Please use HTTPS protocol" }, json)
        assert.contains("Upgrade", res.headers.connection)
        assert.equal("TLS/1.2, HTTP/1.1", res.headers.upgrade)
      end)

      describe("from not trusted_ip", function()
        lazy_setup(function()
          helpers.stop_kong(nil, nil, true)

          assert(helpers.start_kong {
            database    = strategy,
            nginx_conf  = "spec/fixtures/custom_nginx.template",
            trusted_ips = nil,
          })

          proxy_client = helpers.proxy_client()
        end)

        it("blocks HTTP request with HTTPS in x-forwarded-proto", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              Host  = "ssl1.com",
              ["x-forwarded-proto"] = "https"
            }
          })
          assert.res_status(426, res)
        end)
      end)

      describe("from trusted_ip", function()
        lazy_setup(function()
          helpers.stop_kong(nil, nil, true)

          assert(helpers.start_kong {
            database    = strategy,
            nginx_conf  = "spec/fixtures/custom_nginx.template",
            trusted_ips = "127.0.0.1",
          })

          proxy_client = helpers.proxy_client()
        end)

        it("allows HTTP requests with x-forwarded-proto", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              Host  = "example.com",
              ["x-forwarded-proto"] = "https",
            }
          })
          assert.res_status(200, res)
        end)

        it("blocks HTTP requests with invalid x-forwarded-proto", function()
          local res = assert(proxy_client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              Host  = "example.com",
              ["x-forwarded-proto"] = "httpsa"
            }
          })
          assert.res_status(426, res)
        end)
      end)

      describe("blocks with https x-forwarded-proto from untrusted client", function()
        local client

        -- restart kong and use a new client to simulate a connection from an
        -- untrusted ip
        lazy_setup(function()
          assert(helpers.kong_exec("restart -c " .. helpers.test_conf_path, {
            database = strategy,
            trusted_ips = "1.2.3.4", -- explicitly trust an IP that is not us
          }))

          client = helpers.proxy_client()
        end)

        -- despite reloading here with no trusted IPs, this
        it("", function()
          local res = assert(client:send {
            method  = "GET",
            path    = "/status/200",
            headers = {
              Host  = "example.com",
              ["x-forwarded-proto"] = "https"
            }
          })
          assert.res_status(426, res)
        end)
      end)
    end)

    describe("proxy_ssl_name", function()
      local https_client_sni

      before_each(function()
        assert(helpers.kong_exec("restart --conf " .. helpers.test_conf_path ..
                                 " --nginx-conf spec/fixtures/custom_nginx.template", {
          database = strategy,
        }))

        https_client_sni = helpers.proxy_ssl_client()
      end)

      after_each(function()
        https_client_sni:close()
      end)

      describe("properly sets the upstream SNI with preserve_host", function()
        it("true", function()
          local res = assert(https_client_sni:send {
            method  = "GET",
            path    = "/",
            headers = {
              Host  = "ssl3.com"
            },
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("ssl3.com", json.vars.ssl_server_name)
        end)

        it("false", function()
          local res = assert(https_client_sni:send {
            method  = "GET",
            path    = "/",
            headers = {
              Host  = "no-sni.com"
            },
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("localhost", json.vars.ssl_server_name)
        end)

        it("false and IP-based upstream_url", function()
          local res = assert(https_client_sni:send {
            method  = "GET",
            path    = "/",
            headers = {
              Host  = "nil-sni.com"
            }
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("no SNI", json.vars.ssl_server_name)
        end)
      end)
    end)
  end)
end
