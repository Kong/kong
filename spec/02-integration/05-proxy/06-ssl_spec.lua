local ssl_fixtures = require "spec.fixtures.ssl"
local helpers      = require "spec.helpers"
local cjson        = require "cjson"
local fmt          = string.format
local atc_compat = require "kong.router.compat"


local function get_cert(server_name)
  local _, _, stdout = assert(helpers.execute(
    string.format("echo 'GET /' | openssl s_client -connect 0.0.0.0:%d -servername %s",
                  helpers.get_proxy_port(true), server_name)
  ))

  return stdout
end

local mock_tls_server_port = helpers.get_available_port()

local fixtures = {
  http_mock = {
    test_upstream_tls_server = fmt([[
      server {
          server_name example2.com;
          listen %s ssl;

          ssl_certificate        ../spec/fixtures/mtls_certs/example2.com.crt;
          ssl_certificate_key    ../spec/fixtures/mtls_certs/example2.com.key;

          location = / {
              echo 'it works';
          }
      }
    ]], mock_tls_server_port)
  },
}

local function reload_router(flavor)
  _G.kong = {
    configuration = {
      router_flavor = flavor,
    },
  }

  helpers.setenv("KONG_ROUTER_FLAVOR", flavor)

  package.loaded["spec.helpers"] = nil
  package.loaded["kong.global"] = nil
  package.loaded["kong.cache"] = nil
  package.loaded["kong.db"] = nil
  package.loaded["kong.db.schema.entities.routes"] = nil
  package.loaded["kong.db.schema.entities.routes_subschemas"] = nil

  helpers = require "spec.helpers"

  helpers.unsetenv("KONG_ROUTER_FLAVOR")

  fixtures.dns_mock = helpers.dns_mock.new({ mocks_only = true })
  fixtures.dns_mock:A {
    name = "example2.com",
    address = "127.0.0.1",
  }
end


local function gen_route(flavor, r)
  if flavor ~= "expressions" then
    return r
  end

  r.expression = atc_compat.get_expression(r)
  r.priority = tonumber(atc_compat._get_priority(r))

  r.hosts = nil
  r.paths = nil
  r.snis  = nil

  return r
end


for _, flavor in ipairs({ "traditional", "traditional_compatible", "expressions" }) do
for _, strategy in helpers.each_strategy() do
  describe("SSL [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
    local proxy_client
    local https_client

    reload_router(flavor)

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

      bp.routes:insert(gen_route(flavor, {
        protocols = { "https" },
        hosts     = { "global.com" },
        service   = service,
      }))

      local service2 = bp.services:insert {
        name = "api-1",
      }

      bp.routes:insert(gen_route(flavor, {
        protocols = { "https" },
        hosts     = { "example.com", "ssl1.com" },
        service   = service2,
      }))

      bp.routes:insert(gen_route(flavor, {
        protocols = { "https" },
        hosts     = { "sni.example.com" },
        snis      = { "sni.example.com" },
        service   = service2,
      }))

      local service4 = bp.services:insert {
        name     = "api-3",
        protocol = helpers.mock_upstream_ssl_protocol,
        host     = helpers.mock_upstream_hostname,
        port     = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert(gen_route(flavor, {
        protocols     = { "https" },
        hosts         = { "ssl3.com" },
        service       = service4,
        preserve_host = true,
      }))

      local service5 = bp.services:insert {
        name     = "api-4",
        protocol = helpers.mock_upstream_ssl_protocol,
        host     = helpers.mock_upstream_hostname,
        port     = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert(gen_route(flavor, {
        protocols     = { "https" },
        hosts         = { "no-sni.com" },
        service       = service5,
        preserve_host = false,
      }))

      local service6 = bp.services:insert {
        name     = "api-5",
        protocol = helpers.mock_upstream_ssl_protocol,
        host     = "127.0.0.1",
        port     = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert(gen_route(flavor, {
        protocols     = { "https" },
        hosts         = { "nil-sni.com" },
        service       = service6,
        preserve_host = false,
      }))

      local service7 = bp.services:insert {
        name     = "service-7",
        protocol = helpers.mock_upstream_ssl_protocol,
        host     = helpers.mock_upstream_hostname,
        port     = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert(gen_route(flavor, {
        protocols     = { "https" },
        hosts         = { "example.com" },
        paths         = { "/redirect-301" },
        https_redirect_status_code = 301,
        service       = service7,
        preserve_host = false,
      }))

      local service8 = bp.services:insert {
        name     = "service-8",
        protocol = helpers.mock_upstream_ssl_protocol,
        host     = helpers.mock_upstream_hostname,
        port     = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert(gen_route(flavor, {
        protocols     = { "https" },
        hosts         = { "example.com" },
        paths         = { "/redirect-302" },
        https_redirect_status_code = 302,
        service       = service8,
        preserve_host = false,
      }))

      local service_example2 = assert(bp.services:insert {
        name     = "service-example2",
        protocol = "https",
        host     = "example2.com",
        port     = mock_tls_server_port,
      })

      assert(bp.routes:insert(gen_route(flavor, {
        protocols     = { "http" },
        hosts         = { "example2.com" },
        paths         = { "/" },
        service       = service_example2,
      })))

      assert(bp.routes:insert(gen_route(flavor, {
        protocols     = { "http" },
        hosts         = { "example-clear.com" },
        paths         = { "/" },
        service       = service8,
      })))

      local cert = bp.certificates:insert {
        cert     = ssl_fixtures.cert,
        key      = ssl_fixtures.key,
        cert_alt = ssl_fixtures.cert_ecdsa,
        key_alt  = ssl_fixtures.key_ecdsa,

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
        cert_alt = ssl_fixtures.cert_alt_alt_ecdsa,
        key_alt = ssl_fixtures.key_alt_alt_ecdsa,
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

      assert(helpers.start_kong({
        router_flavor = flavor,
        database    = strategy,
        nginx_conf  = "spec/fixtures/custom_nginx.template",
        trusted_ips = "127.0.0.1",
        nginx_http_proxy_ssl_verify = "on",
        nginx_http_proxy_ssl_trusted_certificate = "../spec/fixtures/kong_spec.crt",
        nginx_http_proxy_ssl_verify_depth = "5",
      }, nil, nil, fixtures))

      ngx.sleep(0.01)

      proxy_client = helpers.proxy_client()
      https_client = helpers.proxy_ssl_client()
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("proxy ssl verify", function()
      it("prevents requests to upstream that does not possess a trusted certificate", function()
        helpers.clean_logfile()

        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            Host  = "example2.com",
          },
        })
        local body = assert.res_status(502, res)
        assert.equal("An invalid response was received from the upstream server", body)
        assert.logfile().has.line("upstream SSL certificate verify error: " ..
                                  "(21:unable to verify the first certificate) " ..
                                  "while SSL handshaking to upstream", true, 2)
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

        -- SNI case, see #6425
        res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            ["Host"] = "sni.example.com",
          }
        })

        body = assert.res_status(426, res)
        json = cjson.decode(body)
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
            router_flavor = flavor,
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
            router_flavor = flavor,
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
            router_flavor = flavor,
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
          router_flavor = flavor,
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

  describe("TLS proxy [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
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

      bp.routes:insert(gen_route(flavor, {
        protocols = { "tls" },
        snis     = { "example.com" },
        service   = service,
      }))

      bp.routes:insert(gen_route(flavor, {
        protocols = { "tls" },
        snis      = { "foobar.example.com." },
        service   = service,
      }))

      local cert = bp.certificates:insert {
        cert     = ssl_fixtures.cert,
        key      = ssl_fixtures.key,
        cert_alt = ssl_fixtures.cert_ecdsa,
        key_alt  = ssl_fixtures.key_ecdsa,
      }

      bp.snis:insert {
        name = "example.com",
        certificate = cert,
      }

      assert(helpers.start_kong {
        router_flavor = flavor,
        database    = strategy,
        stream_listen = "127.0.0.1:9020 ssl"
      })


    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("can route normally", function()
      it("sets the default certificate of '*' SNI", function()
        local https_client = helpers.http_client({
          scheme = "https",
          host = "127.0.0.1",
          port = 9020,
          timeout = 60000,
          ssl_verify = false,
          ssl_server_name = "example.com",
        })
        local res = assert(https_client:send {
          method  = "GET",
          path    = "/",
        })

        assert.res_status(404, res)

        local cert = get_cert("example.com")
        -- this fails if the "example.com" SNI wasn't inserted above
        assert.certificate(cert).has.cn("ssl-example.com")
        https_client:close()
      end)
      it("using FQDN (regression for issue 7550)", function()
        local https_client = helpers.http_client({
          scheme = "https",
          host = "127.0.0.1",
          port = 9020,
          timeout = 60000,
          ssl_verify = false,
          ssl_server_name = "foobar.example.com",
        })
        local res = assert(https_client:send {
          method  = "GET",
          path    = "/",
        })

        assert.res_status(404, res)
        https_client:close()
      end)
    end)
  end)

  describe("SSL [#" .. strategy .. ", flavor = " .. flavor .. "]", function()

    reload_router(flavor)

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "certificates",
        "snis",
      })

      local service = bp.services:insert {
        name = "default-cert",
      }

      bp.routes:insert(gen_route(flavor, {
        protocols = { "https" },
        hosts     = { "example.com" },
        service   = service,
      }))

      local cert = bp.certificates:insert {
        cert     = ssl_fixtures.cert,
        key      = ssl_fixtures.key,
        cert_alt = ssl_fixtures.cert_ecdsa,
        key_alt  = ssl_fixtures.key_ecdsa,
      }

      bp.snis:insert {
        name = "*",
        certificate = cert,
      }

      assert(helpers.start_kong {
        router_flavor = flavor,
        database    = strategy,
        nginx_conf  = "spec/fixtures/custom_nginx.template",
      })

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("handshake", function()
      it("sets the default certificate of '*' SNI", function()
        local cert = get_cert("example.com")
        assert.cn("ssl-example.com", cert)
      end)
    end)
  end)

  describe("kong.runloop.certificate invalid SNI [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
    reload_router(flavor)

    lazy_setup(function()
      assert(helpers.start_kong {
        router_flavor = flavor,
        database    = strategy,
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      helpers.clean_logfile()
    end)

    it("normal sni", function()
      get_cert("a.example.com")
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.no.line("invalid SNI", true)
    end)

    it("must not have a port", function()
      get_cert("a.example.com:600")
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line("invalid SNI 'a.example.com:600', must not have a port", true)
    end)

    it("must not have a port (invalid port)", function()
      get_cert("a.example.com:88888")
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line("invalid SNI 'a.example.com:88888', must not have a port", true)
    end)

    it("must not be an IP", function()
      get_cert("127.0.0.1")
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line("invalid SNI '127.0.0.1', must not be an IP", true)
    end)

    it("must not be an IP (with port)", function()
      get_cert("127.0.0.1:443")
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line("invalid SNI '127.0.0.1:443', must not be an IP", true)
    end)

    it("invalid value", function()
      get_cert("256.256.256.256")
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line("invalid SNI '256.256.256.256', invalid value: ", true)
    end)

    it("only one wildcard must be specified", function()
      get_cert("*.exam*le.com")
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line("invalid SNI '*.exam*le.com', only one wildcard must be specified", true)
    end)

    it("wildcard must be leftmost or rightmost character", function()
      get_cert("a.exam*le.com")
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.line("invalid SNI 'a.exam*le.com', wildcard must be leftmost or rightmost character", true)
    end)

  end)
end
end   -- for flavor
