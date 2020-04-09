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
    local proxy_client
    local https_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "certificates",
        "snis",
      })

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

      local service7 = bp.services:insert {
        name     = "service-7",
        protocol = helpers.mock_upstream_ssl_protocol,
        host     = helpers.mock_upstream_hostname,
        port     = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert {
        protocols     = { "https" },
        hosts         = { "example.com" },
        paths         = { "/redirect-301" },
        https_redirect_status_code = 301,
        service       = service7,
        preserve_host = false,
      }

      local service8 = bp.services:insert {
        name     = "service-8",
        protocol = helpers.mock_upstream_ssl_protocol,
        host     = helpers.mock_upstream_hostname,
        port     = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert {
        protocols     = { "https" },
        hosts         = { "example.com" },
        paths         = { "/redirect-302" },
        https_redirect_status_code = 302,
        service       = service8,
        preserve_host = false,
      }

      local service_mockbin = assert(bp.services:insert {
        name     = "service-mockbin",
        url      = "https://mockbin.com/request",
      })

      assert(bp.routes:insert {
        protocols     = { "http" },
        hosts         = { "mockbin.com" },
        paths         = { "/" },
        service       = service_mockbin,
      })

      assert(bp.routes:insert {
        protocols     = { "http" },
        hosts         = { "example-clear.com" },
        paths         = { "/" },
        service       = service8,
      })

      local cert = bp.certificates:insert {
        cert  = ssl_fixtures.cert,
        key   = ssl_fixtures.key,
      }

      bp.snis:insert {
        name = "example.com",
        certificate = cert,
      }

      bp.snis:insert {
        name = "ssl1.com",
        certificate = cert,
      }

      -- wildcard tests

      local certificate_alt = bp.certificates:insert {
        cert = ssl_fixtures.cert_alt,
        key = ssl_fixtures.key_alt,
      }

      local certificate_alt_alt = bp.certificates:insert {
        cert = ssl_fixtures.cert_alt_alt,
        key = ssl_fixtures.key_alt_alt,
      }

      bp.snis:insert {
        name = "*.wildcard.com",
        certificate = certificate_alt,
      }

      bp.snis:insert {
        name = "wildcard.*",
        certificate = certificate_alt,
      }

      bp.snis:insert {
        name = "wildcard.org",
        certificate = certificate_alt_alt,
      }

      bp.snis:insert {
        name = "test.wildcard.*",
        certificate = certificate_alt_alt,
      }

      bp.snis:insert {
        name = "*.www.wildcard.com",
        certificate = certificate_alt_alt,
      }

      -- /wildcard tests

      assert(helpers.start_kong {
        database    = strategy,
        nginx_conf  = "spec/fixtures/custom_nginx.template",
        trusted_ips = "127.0.0.1",
        nginx_http_proxy_ssl_verify = "on",
        nginx_http_proxy_ssl_trusted_certificate = "../spec/fixtures/kong_spec.crt",
      })

      proxy_client = helpers.proxy_client()
      https_client = helpers.proxy_ssl_client()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("proxy ssl verify", function()
      it("prevents requests to upstream that does not possess a trusted certificate", function()
        -- setup: cleanup logs
        local test_error_log_path = helpers.test_conf.nginx_err_logs
        os.execute(":> " .. test_error_log_path)

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            Host  = "mockbin.com",
          },
        })
        local body = assert.res_status(502, res)
        assert.equal("An invalid response was received from the upstream server", body)

        local pl_file = require("pl.file")

        helpers.wait_until(function()
          -- Assertion: there should be [error] resulting from
          -- TLS handshake failure

          local logs = pl_file.read(test_error_log_path)
          local found = false

          for line in logs:gmatch("[^\r\n]+") do
            if line:find("upstream SSL certificate verify error: " ..
                         "(20:unable to get local issuer certificate) " ..
                         "while SSL handshaking to upstream", nil, true)
            then
              found = true

            else
              assert.not_match("[error]", line, nil, true)
            end
          end

          if found then
              return true
          end
        end, 2)
      end)

      it("trusted certificate, request goes through", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            Host  = "example-clear.com",
          }
        })
        assert.res_status(200, res)
      end)
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
        assert.certificate(cert).has.cn("localhost")
      end)

      it("sets the configured SSL certificate if SNI match", function()
        local cert = get_cert("ssl1.com")
        assert.certificate(cert).has.cn("ssl-example.com")

        cert = get_cert("example.com")
        assert.certificate(cert).has.cn("ssl-example.com")
      end)

      describe("wildcard sni", function()
        it("matches *.wildcard.com (prefix)", function()
          local cert = get_cert("test.wildcard.com")
          assert.matches("CN%s*=%s*ssl%-alt%.com", cert)
        end)

        it("matches wildcard.* (suffix)", function()
          local cert = get_cert("wildcard.eu")
          assert.matches("CN%s*=%s*ssl%-alt%.com", cert)
        end)

        it("respects matching priorities (exact first)", function()
          local cert = get_cert("wildcard.org")
          assert.matches("CN%s*=%s*ssl%-alt%-alt%.com", cert)
        end)

        it("respects matching priorities (prefix second)", function()
          local cert = get_cert("test.wildcard.com")
          assert.matches("CN%s*=%s*ssl%-alt%.com", cert)
        end)

        it("respects matching priorities (suffix third)", function()
          local cert = get_cert("test.wildcard.org")
          assert.matches("CN%s*=%s*ssl%-alt%-alt%.com", cert)
        end)

        it("matches *.www.wildcard.com", function()
          local cert = get_cert("test.www.wildcard.com")
          assert.matches("CN%s*=%s*ssl%-alt%-alt%.com", cert)
        end)
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

      it("returns 301 when route has https_redirect_status_code set to 301", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/redirect-301",
          headers = {
            ["Host"] = "example.com",
          }
        })

        assert.res_status(301, res)
        assert.equal("https://example.com/redirect-301", res.headers.location)
      end)

      it("returns 302 when route has https_redirect_status_code set to 302", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/redirect-302?foo=bar",
          headers = {
            ["Host"] = "example.com",
          }
        })

        assert.res_status(302, res)
        assert.equal("https://example.com/redirect-302?foo=bar", res.headers.location)
      end)

      describe("from not trusted_ip", function()
        lazy_setup(function()
          assert(helpers.restart_kong {
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
          assert(helpers.restart_kong {
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
          assert(helpers.restart_kong {
            database = strategy,
            nginx_conf  = "spec/fixtures/custom_nginx.template",
            trusted_ips = "1.2.3.4", -- explicitly trust an IP that is not us
          })

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
        assert(helpers.restart_kong {
          database = strategy,
          nginx_conf  = "spec/fixtures/custom_nginx.template",
        })

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

  describe("TLS proxy [#" .. strategy .. "]", function()
    local https_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "certificates",
        "snis",
      })

      local service = bp.services:insert {
        name = "svc-http",
        protocol = "tcp",
        host = helpers.get_proxy_ip(),
        port = helpers.get_proxy_port(),
      }

      bp.routes:insert {
        protocols = { "tls" },
        snis     = { "example.com" },
        service   = service,
      }

      local cert = bp.certificates:insert {
        cert  = ssl_fixtures.cert,
        key   = ssl_fixtures.key,
      }

      bp.snis:insert {
        name = "example.com",
        certificate = cert,
      }

      assert(helpers.start_kong {
        database    = strategy,
        stream_listen = "127.0.0.1:9020 ssl"
      })

    https_client = helpers.http_client("127.0.0.1", 9020, 60000)
    assert(https_client:ssl_handshake(nil, "example.com", false)) -- explicit no-verify
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      https_client:close()
    end)

    describe("can route normally", function()
      it("sets the default certificate of '*' SNI", function()
        local res = assert(https_client:send {
          method  = "GET",
          path    = "/",
        })

        assert.res_status(404, res)

        local cert = get_cert("example.com")
        -- this fails if the "example.com" SNI wasn't inserted above
        assert.certificate(cert).has.cn("ssl-example.com")
      end)
    end)
  end)
end
