local helpers = require "spec.helpers"
local ssl_fixtures = require "spec.fixtures.ssl"
local atc_compat = require "kong.router.compat"


local other_ca_cert = [[
-----BEGIN CERTIFICATE-----
MIIEvjCCAqagAwIBAgIJALabx/Nup200MA0GCSqGSIb3DQEBCwUAMBMxETAPBgNV
BAMMCFlvbG80Mi4xMCAXDTE5MDkxNTE2Mjc1M1oYDzIxMTkwODIyMTYyNzUzWjAT
MREwDwYDVQQDDAhZb2xvNDIuMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
ggIBANIW67Ay0AtTeBY2mORaGet/VPL5jnBRz0zkZ4Jt7fEq3lbxYaJBnFI8wtz3
bHLtLsxkvOFujEMY7HVd+iTqbJ7hLBtK0AdgXDjf+HMmoWM7x0PkZO+3XSqyRBbI
YNoEaQvYBNIXrKKJbXIU6higQaXYszeN8r3+RIbcTIlZxy28msivEGfGTrNujQFc
r/eyf+TLHbRqh0yg4Dy/U/T6fqamGhFrjupRmOMugwF/BHMH2JHhBYkkzuZLgV2u
7Yh1S5FRlh11am5vWuRSbarnx72hkJ99rUb6szOWnJKKew8RSn3CyhXbS5cb0QRc
ugRc33p/fMucJ4mtCJ2Om1QQe83G1iV2IBn6XJuCvYlyWH8XU0gkRxWD7ZQsl0bB
8AFTkVsdzb94OM8Y6tWI5ybS8rwl8b3r3fjyToIWrwK4WDJQuIUx4nUHObDyw+KK
+MmqwpAXQWbNeuAc27FjuJm90yr/163aGuInNY5Wiz6CM8WhFNAi/nkEY2vcxKKx
irSdSTkbnrmLFAYrThaq0BWTbW2mwkOatzv4R2kZzBUOiSjRLPnbyiPhI8dHLeGs
wMxiTXwyPi8iQvaIGyN4DPaSEiZ1GbexyYFdP7sJJD8tG8iccbtJYquq3cDaPTf+
qv5M6R/JuMqtUDheLSpBNK+8vIe5e3MtGFyrKqFXdynJtfHVAgMBAAGjEzARMA8G
A1UdEwQIMAYBAf8CAQAwDQYJKoZIhvcNAQELBQADggIBAK0BmL5B1fPSMbFy8Hbc
/ESEunt4HGaRWmZZSa/aOtTjhKyDXLLJZz3C4McugfOf9BvvmAOZU4uYjfHTnNH2
Z3neBkdTpQuJDvrBPNoCtJns01X/nuqFaTK/Tt9ZjAcVeQmp51RwhyiD7nqOJ/7E
Hp2rC6gH2ABXeexws4BDoZPoJktS8fzGWdFBCHzf4mCJcb4XkI+7GTYpglR818L3
dMNJwXeuUsmxxKScBVH6rgbgcEC/6YwepLMTHB9VcH3X5VCfkDIyPYLWmvE0gKV7
6OU91E2Rs8PzbJ3EuyQpJLxFUQp8ohv5zaNBlnMb76UJOPR6hXfst5V+e7l5Dgwv
Dh4CeO46exmkEsB+6R3pQR8uOFtubH2snA0S3JA1ji6baP5Y9Wh9bJ5McQUgbAPE
sCRBFoDLXOj3EgzibohC5WrxN3KIMxlQnxPl3VdQvp4gF899mn0Z9V5dAsGPbxRd
quE+DwfXkm0Sa6Ylwqrzu2OvSVgbMliF3UnWbNsDD5KcHGIaFxVC1qkwK4cT3pyS
58i/HAB2+P+O+MltQUDiuw0OSUFDC0IIjkDfxLVffbF+27ef9C5NG81QlwTz7TuN
zeigcsBKooMJTszxCl6dtxSyWTj7hJWXhy9pXsm1C1QulG6uT4RwCa3m0QZoO7G+
6Wu6lP/kodPuoNubstIuPdi2
-----END CERTIFICATE-----
]]

local fixtures = {
  http_mock = {
    upstream_mtls = [[
      server {
          server_name example.com;
          listen 16798 ssl;

          ssl_certificate        ../spec/fixtures/mtls_certs/example.com.crt;
          ssl_certificate_key    ../spec/fixtures/mtls_certs/example.com.key;
          ssl_client_certificate ../spec/fixtures/mtls_certs/ca.crt;
          ssl_verify_client      on;
          ssl_session_tickets    off;
          ssl_session_cache      off;
          keepalive_requests     0;

          location = / {
              add_header 'X-Cert' $ssl_client_escaped_cert;
              echo 'it works';
          }
      }
    ]],
    upstream_tls = [[
      server {
          server_name example.com;
          listen 16799 ssl;

          ssl_certificate        ../spec/fixtures/mtls_certs/example.com.crt;
          ssl_certificate_key    ../spec/fixtures/mtls_certs/example.com.key;
          ssl_session_tickets    off;
          ssl_session_cache      off;
          keepalive_requests     0;

          location = / {
              echo 'it works';
          }
      }
    ]]
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
    name = "example.com",
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

  r.destinations = nil

  return r
end

local function gen_plugin(route)
  return {
    name = "pre-function",
    route = { id = route.id },
    config = {
      access = {
        [[
          kong.service.request.enable_buffering()
        ]]
      }
    }
  }
end


for _, flavor in ipairs({ "traditional", "traditional_compatible" }) do
for _, strategy in helpers.each_strategy() do
  describe("overriding upstream TLS parameters for database [#" .. strategy .. ", flavor = " .. flavor .. "]", function()
    local admin_client
    local bp
    local service_mtls, service_tls
    local certificate, certificate_bad, ca_certificate
    local upstream
    local service_mtls_upstream

    local tls_service_mtls, tls_service_tls
    local tls_upstream
    local tls_service_mtls_upstream

    local route_mtls_buffered_proxying, route_tls_buffered_proxying, route_mtls_upstream_buffered_proxying

    reload_router(flavor)

    lazy_setup(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "certificates",
        "ca_certificates",
        "upstreams",
        "targets",
      })

      service_mtls = assert(bp.services:insert({
        name = "protected-service-mtls",
        url = "https://127.0.0.1:16798/",
      }))

      service_tls = assert(bp.services:insert({
        name = "protected-service",
        url = "https://example.com:16799/", -- domain name needed for hostname check
      }))

      upstream = assert(bp.upstreams:insert({
        name = "backend-mtls",
      }))

      assert(bp.targets:insert({
        upstream = { id = upstream.id, },
        target = "127.0.0.1:16798",
      }))

      service_mtls_upstream = assert(bp.services:insert({
        name = "protected-service-mtls-upstream",
        url = "https://backend-mtls/",
      }))

      certificate = assert(bp.certificates:insert({
        cert = ssl_fixtures.cert_client,
        key = ssl_fixtures.key_client,
      }))

      certificate_bad = assert(bp.certificates:insert({
        cert = ssl_fixtures.cert, -- this cert is *not* trusted by upstream
        key = ssl_fixtures.key,
      }))

      ca_certificate = assert(bp.ca_certificates:insert({
        cert = ssl_fixtures.cert_ca,
      }))

      assert(bp.routes:insert(gen_route(flavor,{
        service = { id = service_mtls.id, },
        hosts = { "example.com", },
        paths = { "/mtls", },
      })))

      assert(bp.routes:insert(gen_route(flavor,{
        service = { id = service_tls.id, },
        hosts = { "example.com", },
        paths = { "/tls", },
      })))

      assert(bp.routes:insert(gen_route(flavor,{
        service = { id = service_mtls_upstream.id, },
        hosts = { "example.com", },
        paths = { "/mtls-upstream", },
      })))

      route_mtls_buffered_proxying = assert(bp.routes:insert(gen_route(flavor,{
        service = { id = service_mtls.id, },
        hosts = { "example.com", },
        paths = { "/mtls-buffered-proxying", },
      })))

      route_tls_buffered_proxying = assert(bp.routes:insert(gen_route(flavor,{
        service = { id = service_tls.id, },
        hosts = { "example.com", },
        paths = { "/tls-buffered-proxying", },
      })))

      route_mtls_upstream_buffered_proxying = assert(bp.routes:insert(gen_route(flavor,{
        service = { id = service_mtls_upstream.id, },
        hosts = { "example.com", },
        paths = { "/mtls-upstream-buffered-proxying", },
      })))

      -- use pre-function to enable buffered_proxying in order to trigger the
      -- `ngx.location.capture("/kong_buffered_http")` in `Kong.response()`
      assert(bp.plugins:insert(gen_plugin(route_mtls_buffered_proxying)))
      assert(bp.plugins:insert(gen_plugin(route_tls_buffered_proxying)))
      assert(bp.plugins:insert(gen_plugin(route_mtls_upstream_buffered_proxying)))

      -- tls
      tls_service_mtls = assert(bp.services:insert({
        name = "tls-protected-service-mtls",
        url = "tls://127.0.0.1:16798",
      }))

      tls_service_tls = assert(bp.services:insert({
        name = "tls-protected-service",
        url = "tls://example.com:16799", -- domain name needed for hostname check
      }))

      tls_upstream = assert(bp.upstreams:insert({
        name = "tls-backend-mtls",
      }))

      assert(bp.targets:insert({
        upstream = { id = tls_upstream.id, },
        target = "example.com:16798",
      }))

      tls_service_mtls_upstream = assert(bp.services:insert({
        name = "tls-protected-service-mtls-upstream",
        url = "tls://tls-backend-mtls",
        host = "example.com"
      }))

      assert(bp.routes:insert(gen_route(flavor,{
        service = { id = tls_service_mtls.id, },
        destinations = {
          {
            port = 19000,
          },
        },
        protocols = {
          "tls",
        },
      })))

      assert(bp.routes:insert(gen_route(flavor,{
        service = { id = tls_service_tls.id, },
        destinations = {
          {
            port = 19001,
          },
        },
        protocols = {
          "tls",
        },
      })))

      assert(bp.routes:insert(gen_route(flavor,{
        service = { id = tls_service_mtls_upstream.id, },
        destinations = {
          {
            port = 19002,
          },
        },
        protocols = {
          "tls",
        },
      })))


      assert(helpers.start_kong({
        router_flavor = flavor,
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        stream_listen = helpers.get_proxy_ip(false) .. ":19000,"
                     .. helpers.get_proxy_ip(false) .. ":19001,"
                     .. helpers.get_proxy_ip(false) .. ":19002,"
                     .. helpers.get_proxy_ip(false) .. ":19003",
      }, nil, nil, fixtures))

      admin_client = assert(helpers.admin_client())
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)
  
    local function get_tls_service_id(subsystems)
      if subsystems == "http" then
        return service_mtls.id
      else
        return tls_service_mtls.id
      end      
    end

    local function get_proxy_client(subsystems, stream_port)
      if subsystems == "http" then
        return assert(helpers.proxy_client())
      else
         return assert(helpers.proxy_client(20000, stream_port))
      end
    end

    local function wait_for_all_config_update(subsystems) 
      local opt = {}
      if subsystems == "stream" then
        opt.stream_enabled = true
        opt.stream_port = 19003
      end

      helpers.wait_for_all_config_update(opt)
    end

    for _, subsystems in pairs({"http", "stream"}) do
    describe(subsystems .. " mutual TLS authentication against upstream with Service object", function()
      describe("no client certificate supplied", function()
        it("accessing protected upstream", function()
          local proxy_client = get_proxy_client(subsystems, 19000)
          local res = assert(proxy_client:send {
            path    = "/mtls",
            headers = {
              ["Host"] = "example.com",
            }
          })

          local body = assert.res_status(400, res)
          assert.matches("400 No required SSL certificate was sent", body, nil, true)
          assert(proxy_client:close())
        end)

        -- buffered_proxying
        if subsystems == "http" then
          it("accessing protected upstream, buffered_proxying = true", function()
            local proxy_client = get_proxy_client(subsystems, 19000)
            local res = assert(proxy_client:send {
              path    = "/mtls-buffered-proxying",
              headers = {
                ["Host"] = "example.com",
              }
            })

            local body = assert.res_status(400, res)
            assert.matches("400 No required SSL certificate was sent", body, nil, true)
            assert(proxy_client:close())
          end)
        end
      end)

      describe(subsystems .. " #db client certificate supplied via service.client_certificate", function()
        lazy_setup(function()
          local service_id = get_tls_service_id(subsystems)
          local res = assert(admin_client:patch("/services/" .. service_id, {
            body = {
              client_certificate = { id = certificate.id, },
            },
            headers = { ["Content-Type"] = "application/json" },
          }))
          assert.res_status(200, res)
        end)

        it("accessing protected upstream", function()
          helpers.wait_until(function()
            local proxy_client = get_proxy_client(subsystems, 19000)
            local path
            if subsystems == "http" then
              path = "/mtls"
            else
              path = "/"
            end
            local res = assert(proxy_client:send {
              path    = path,
              headers = {
                ["Host"] = "example.com",
              }
            })

            return pcall(function()
              local body = assert.res_status(200, res)
              assert.equals("it works", body)
              assert(proxy_client:close())
            end)
          end, 10)
        end)

        -- buffered_proxying
        if subsystems == "http" then
          it("accessing protected upstream, buffered_proxying = true", function()
            helpers.wait_until(function()
              local proxy_client = get_proxy_client(subsystems, 19000)
              local path = "/mtls-buffered-proxying"
              local res = assert(proxy_client:send {
                path    = path,
                headers = {
                  ["Host"] = "example.com",
                }
              })

              return pcall(function()
                local body = assert.res_status(200, res)
                assert.equals("it works", body)
                assert(proxy_client:close())
              end)
            end, 10)
          end)
        end

        it("send updated client certificate", function ()
          local proxy_client = get_proxy_client(subsystems, 19000)
          local path
          if subsystems == "http" then
            path = "/mtls"
          else
            path = "/"
          end
          local res = assert(proxy_client:send {
            path    = path,
            headers = {
              ["Host"] = "example.com",
            }
          })
          assert.res_status(200, res)
          local res_cert = res.headers["X-Cert"]
          assert(proxy_client:close())

          -- buffered_proxying
          local res_cert_buffered
          if subsystems == "http" then
            local proxy_client = get_proxy_client(subsystems, 19000)
            local res = assert(proxy_client:send {
              path    = "/mtls-buffered-proxying",
              headers = {
                ["Host"] = "example.com",
              }
            })
            assert.res_status(200, res)
            res_cert_buffered = res.headers["X-Cert"]
            assert(proxy_client:close())
          end

          res = admin_client:patch("/certificates/" .. certificate.id, {
            body = {
              cert = ssl_fixtures.cert_client2,
              key = ssl_fixtures.key_client2,
            },
            headers = { ["Content-Type"] = "application/json" }
          })
          assert.res_status(200, res)

          wait_for_all_config_update(subsystems)

          local proxy_client2 = get_proxy_client(subsystems, 19000)
          if subsystems == "http" then
            path = "/mtls"
          else
            path = "/"
          end
          res = assert(proxy_client2:send {
            path    = path,
            headers = {
              ["Host"] = "example.com",
            }
          })
          assert.res_status(200, res)
          local res_cert2 = res.headers["X-Cert"]
          assert.not_equals(res_cert, res_cert2)

          -- buffered_proxying
          local res_cert2_buffered
          if subsystems == "http" then
            res = assert(proxy_client2:send {
              path    = "/mtls-buffered-proxying",
              headers = {
                ["Host"] = "example.com",
              }
            })
            assert.res_status(200, res)
            res_cert2_buffered = res.headers["X-Cert"]
            assert.not_equals(res_cert_buffered, res_cert2_buffered)
          end

          -- restore old
          res = admin_client:patch("/certificates/" .. certificate.id, {
            body = {
              cert = ssl_fixtures.cert_client,
              key = ssl_fixtures.key_client,
            },
            headers = { ["Content-Type"] = "application/json" }
          })
          assert.res_status(200, res)
          assert(proxy_client2:close())
        end)

        it("remove client_certificate removes access", function()
          local service_id = get_tls_service_id(subsystems)
          local res = assert(admin_client:patch("/services/" .. service_id, {
            body = {
              client_certificate = ngx.null,
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          local body
          helpers.wait_until(function()
            local proxy_client= get_proxy_client(subsystems, 19000)
            res = assert(proxy_client:send {
              path    = "/mtls",
              headers = {
                ["Host"] = "example.com",
              }
            })

            return pcall(function()
              body = assert.res_status(400, res)
              assert(proxy_client:close())
            end)
          end, 10)

          assert.matches("400 No required SSL certificate was sent", body, nil, true)

          -- buffered_proxying
          if subsystems == "http" then
            helpers.wait_until(function()
              local proxy_client= get_proxy_client(subsystems, 19000)
              res = assert(proxy_client:send {
                path    = "/mtls-buffered-proxying",
                headers = {
                  ["Host"] = "example.com",
                }
              })

              return pcall(function()
                body = assert.res_status(400, res)
                assert(proxy_client:close())
              end)
            end, 10)

            assert.matches("400 No required SSL certificate was sent", body, nil, true)
          end
        end)
      end)
    end)

    describe(subsystems .. " mutual TLS authentication against upstream with Upstream object", function()
      describe("no client certificate supplied", function()
        it("accessing protected upstream", function()
          local proxy_client= get_proxy_client(subsystems, 19002)
          local res = assert(proxy_client:send {
            path    = "/mtls-upstream",
            headers = {
              ["Host"] = "example.com",
            }
          })

          local body = assert.res_status(400, res)
          assert.matches("400 No required SSL certificate was sent", body, nil, true)
          assert(proxy_client:close())
        end)

        -- buffered_proxying
        if subsystems == "http" then
          it("accessing protected upstream, buffered_proxying = true", function()
            local proxy_client= get_proxy_client(subsystems, 19002)
            local res = assert(proxy_client:send {
              path    = "/mtls-upstream-buffered-proxying",
              headers = {
                ["Host"] = "example.com",
              }
            })

            local body = assert.res_status(400, res)
            assert.matches("400 No required SSL certificate was sent", body, nil, true)
            assert(proxy_client:close())
          end)
        end
      end)

      describe("#db client certificate supplied via upstream.client_certificate", function()
        lazy_setup(function()
          local upstream_id
          if subsystems == "http" then
             upstream_id = upstream.id
          else
            upstream_id = tls_upstream.id
          end
          local res = assert(admin_client:patch("/upstreams/" .. upstream_id, {
            body = {
              client_certificate = { id = certificate.id, },
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)
        end)

        it("accessing protected upstream", function()
          helpers.wait_until(function()
            local proxy_client = get_proxy_client(subsystems, 19002)
            local path
            if subsystems == "http" then
              path = "/mtls-upstream"
            else
              path = "/"
            end
            local res = assert(proxy_client:send {
              path    = path,
              headers = {
                ["Host"] = "example.com",
              }
            })

            return pcall(function()
              local body = assert.res_status(200, res)
              assert.equals("it works", body)
              assert(proxy_client:close())
            end)
          end, 10)
        end)

        -- buffered_proxying
        if subsystems == "http" then
          it("accessing protected upstream, buffered_proxying = true", function()
            helpers.wait_until(function()
              local proxy_client = get_proxy_client(subsystems, 19002)
              local path = "/mtls-upstream-buffered-proxying"
              local res = assert(proxy_client:send {
                path    = path,
                headers = {
                  ["Host"] = "example.com",
                }
              })

              return pcall(function()
                local body = assert.res_status(200, res)
                assert.equals("it works", body)
                assert(proxy_client:close())
              end)
            end, 10)
          end)
        end

        it("remove client_certificate removes access", function()
          local upstream_id
          if subsystems == "http" then
             upstream_id = upstream.id
          else
            upstream_id = tls_upstream.id
          end
          local res = assert(admin_client:patch("/upstreams/" .. upstream_id, {
            body = {
              client_certificate = ngx.null,
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          wait_for_all_config_update(subsystems)

          local body
          helpers.wait_until(function()
            local proxy_client = get_proxy_client(subsystems, 19002)
            res = assert(proxy_client:send {
              path    = "/mtls-upstream",
              headers = {
                ["Host"] = "example.com",
              }
            })

            return pcall(function()
              body = assert.res_status(400, res)
              assert(proxy_client:close())
            end)
          end, 10)

          assert.matches("400 No required SSL certificate was sent", body, nil, true)

          -- buffered_proxying
          if subsystems == "http" then
            helpers.wait_until(function()
              local proxy_client = get_proxy_client(subsystems, 19002)
              res = assert(proxy_client:send {
                path    = "/mtls-upstream-buffered-proxying",
                headers = {
                  ["Host"] = "example.com",
                }
              })

              return pcall(function()
                body = assert.res_status(400, res)
                assert(proxy_client:close())
              end)
            end, 10)

            assert.matches("400 No required SSL certificate was sent", body, nil, true)
          end
        end)
      end)

      describe("#db when both Service.client_certificate and Upstream.client_certificate are set, Service.client_certificate takes precedence", function()
        lazy_setup(function()
          local upstream_id
          local service_mtls_upstream_id
          if subsystems == "http" then
            upstream_id = upstream.id
            service_mtls_upstream_id = service_mtls_upstream.id
          else
            upstream_id = tls_upstream.id
            service_mtls_upstream_id = tls_service_mtls_upstream.id
          end
          local res = assert(admin_client:patch("/upstreams/" .. upstream_id, {
            body = {
              client_certificate = { id = certificate_bad.id, },
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          res = assert(admin_client:patch("/services/" .. service_mtls_upstream_id, {
            body = {
              client_certificate = { id = certificate.id, },
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          wait_for_all_config_update(subsystems)
        end)

        it("access is allowed because Service.client_certificate overrides Upstream.client_certificate", function()
          helpers.wait_until(function()
            local proxy_client = get_proxy_client(subsystems, 19002)
            local path
            if subsystems == "http" then
              path = "/mtls-upstream"
            else
              path = "/"
            end
            local res = assert(proxy_client:send {
              path    = path,
              headers = {
                ["Host"] = "example.com",
              }
            })

            return pcall(function()
              local body = assert.res_status(200, res)
              assert.equals("it works", body)
              assert(proxy_client:close())
            end)
          end, 10)
        end)

        -- buffered_proxying
        if subsystems == "http" then
          it("access is allowed because Service.client_certificate overrides Upstream.client_certificate, buffered_proxy = true", function()
            helpers.wait_until(function()
              local proxy_client = get_proxy_client(subsystems, 19002)
              local path = "/mtls-upstream-buffered-proxying"
              local res = assert(proxy_client:send {
                path    = path,
                headers = {
                  ["Host"] = "example.com",
                }
              })

              return pcall(function()
                local body = assert.res_status(200, res)
                assert.equals("it works", body)
                assert(proxy_client:close())
              end)
            end, 10)
          end)
        end
      end)
    end)

    describe(subsystems .. " TLS verification options against upstream", function()
      describe("tls_verify", function()
        it("default is off", function()
          local proxy_client = get_proxy_client(subsystems, 19001)
          local path
          if subsystems == "http" then
            path = "/tls"
          else
            path = "/"
          end
          local res = proxy_client:send {
            path    = path,
            headers = {
              ["Host"] = "example.com",
            }
          }
          local body = assert.res_status(200, res)
          assert.equals("it works", body)
          assert(proxy_client:close())
        end)

        -- buffered_proxying
        if subsystems == "http" then
          it("default is off, buffered_proxying = true", function()
            local proxy_client = get_proxy_client(subsystems, 19001)
            local path = "/tls-buffered-proxying"
            local res = proxy_client:send {
              path    = path,
              headers = {
                ["Host"] = "example.com",
              }
            }
            local body = assert.res_status(200, res)
            assert.equals("it works", body)
            assert(proxy_client:close())
          end)
        end

        it("#db turn it on, request is blocked", function()
          local service_tls_id
          if subsystems == "http" then
            service_tls_id = service_tls.id
          else
            service_tls_id = tls_service_tls.id
          end
          local res = assert(admin_client:patch("/services/" .. service_tls_id, {
            body = {
              tls_verify = true,
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          wait_for_all_config_update(subsystems)

          local body
          helpers.wait_until(function()
            local proxy_client = get_proxy_client(subsystems, 19001)
            local err
            res, err = proxy_client:send {
              path    = "/tls",
              headers = {
                ["Host"] = "example.com",
              }
            }
            if subsystems == "http" then
              return pcall(function()
                body = assert.res_status(502, res)
                assert(proxy_client:close())
              end)
            else
              return pcall(function()
                assert.equals("connection reset by peer", err)
                assert(proxy_client:close())
              end)
            end
          end, 10)
          
          if subsystems == "http" then
            assert.matches("An invalid response was received from the upstream server", body)
          end

          -- buffered_proxying
          if subsystems == "http" then
            helpers.wait_until(function()
              local proxy_client = get_proxy_client(subsystems, 19001)
              res = proxy_client:send {
                path    = "/tls-buffered-proxying",
                headers = {
                  ["Host"] = "example.com",
                }
              }
              return pcall(function()
                body = assert.res_status(502, res)
                assert(proxy_client:close())
              end)
            end, 10)

            assert.matches("An invalid response was received from the upstream server", body)
          end
        end)
      end)

      describe("ca_certificates", function()
        it("#db request is allowed through once correct CA certificate is set", function()
          local service_tls_id
          if subsystems == "http" then
            service_tls_id = service_tls.id
          else
            service_tls_id = tls_service_tls.id
          end
          local res = assert(admin_client:patch("/services/" .. service_tls_id, {
            body = {
              tls_verify = true,
              ca_certificates = { ca_certificate.id, },
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          wait_for_all_config_update(subsystems)

          local body
          helpers.wait_until(function()
            local proxy_client = get_proxy_client(subsystems, 19001)
            local path
            if subsystems == "http" then
              path = "/tls"
            else
              path = "/"
            end
            local res = proxy_client:send {
              path    = path,
              headers = {
                ["Host"] = "example.com",
              }
            }
            return pcall(function()
              body = assert.res_status(200, res)
              assert(proxy_client:close())
            end)
          end, 10)

          assert.equals("it works", body)

          -- buffered_proxying
          if subsystems == "http" then
            helpers.wait_until(function()
              local proxy_client = get_proxy_client(subsystems, 19001)
              local path = "/tls-buffered-proxying"
              local res = proxy_client:send {
                path    = path,
                headers = {
                  ["Host"] = "example.com",
                }
              }
              return pcall(function()
                body = assert.res_status(200, res)
                assert(proxy_client:close())
              end)
            end, 10)

            assert.equals("it works", body)
          end
        end)

        it("#db request is not allowed through once the CA certificate is updated to other ca", function()
          local res = assert(admin_client:patch("/ca_certificates/" .. ca_certificate.id, {
            body = {
              cert = other_ca_cert,
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          wait_for_all_config_update(subsystems)

          local body
          helpers.wait_until(function()
            local proxy_client = get_proxy_client(subsystems, 19001)
            local path
            if subsystems == "http" then
              path = "/tls"
            else
              path = "/"
            end
            local res, err = proxy_client:send {
              path    = path,
              headers = {
                ["Host"] = "example.com",
              }
            }

            if subsystems == "http" then
              return pcall(function()
                body = assert.res_status(502, res)
                assert(proxy_client:close())
              end)
            else
              return pcall(function()
                assert.equals("connection reset by peer", err)
                assert(proxy_client:close())
              end)
            end
          end, 10)

          if subsystems == "http" then
            assert.matches("An invalid response was received from the upstream server", body)
          end

          -- buffered_proxying
          if subsystems == "http" then
            helpers.wait_until(function()
              local proxy_client = get_proxy_client(subsystems, 19001)
              local path = "/tls-buffered-proxying"
              local res = proxy_client:send {
                path    = path,
                headers = {
                  ["Host"] = "example.com",
                }
              }

              return pcall(function()
                 body = assert.res_status(502, res)
                 assert(proxy_client:close())
              end)
            end, 10)
            assert.matches("An invalid response was received from the upstream server", body)
          end
        end)

        it("#db request is allowed through once the CA certificate is updated back to the correct ca", function()
          local res = assert(admin_client:patch("/ca_certificates/" .. ca_certificate.id, {
            body = {
              cert = ssl_fixtures.cert_ca,
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          wait_for_all_config_update(subsystems)

          local body
          helpers.wait_until(function()
            local proxy_client = get_proxy_client(subsystems, 19001)
            local path
            if subsystems == "http" then
              path = "/tls"
            else
              path = "/"
            end
            local res = proxy_client:send {
              path    = path,
              headers = {
                ["Host"] = "example.com",
              }
            }

            return pcall(function()
              body = assert.res_status(200, res)
              assert(proxy_client:close())
            end)
          end, 10)

          assert.equals("it works", body)

          -- buffered_proxying
          if subsystems == "http" then
            helpers.wait_until(function()
              local proxy_client = get_proxy_client(subsystems, 19001)
              local path = "/tls-buffered-proxying"
              local res = proxy_client:send {
                path    = path,
                headers = {
                  ["Host"] = "example.com",
                }
              }

              return pcall(function()
                body = assert.res_status(200, res)
                assert(proxy_client:close())
              end)
            end, 10)
            assert.equals("it works", body)
          end
        end)
      end)

      describe("#db tls_verify_depth", function()
        lazy_setup(function()
          local service_tls_id
          if subsystems == "http" then
            service_tls_id = service_tls.id
          else
            service_tls_id = tls_service_tls.id
          end
          local res = assert(admin_client:patch("/services/" .. service_tls_id, {
            body = {
              tls_verify = true,
              ca_certificates = { ca_certificate.id, },
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          wait_for_all_config_update(subsystems)

        end)

        it("request is not allowed through if depth limit is too low", function()
          local service_tls_id
          if subsystems == "http" then
            service_tls_id = service_tls.id
          else
            service_tls_id = tls_service_tls.id
          end
          local res = assert(admin_client:patch("/services/" .. service_tls_id, {
            body = {
              tls_verify_depth = 0,
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          wait_for_all_config_update(subsystems)

          local body
          helpers.wait_until(function()
            local proxy_client = get_proxy_client(subsystems, 19001)
            local res, err = proxy_client:send {
              path    = "/tls",
              headers = {
                ["Host"] = "example.com",
              }
            }

            if subsystems == "http" then
              return pcall(function()
                body = assert.res_status(502, res)
                assert(proxy_client:close())
              end)
            else
              return pcall(function()
                assert.equals("connection reset by peer", err)
                assert(proxy_client:close())
              end)
            end
          end, 10)
          if subsystems == "http" then
            assert.matches("An invalid response was received from the upstream server", body)
          end

          -- buffered_proxying
          if subsystems == "http" then
            helpers.wait_until(function()
              local proxy_client = get_proxy_client(subsystems, 19001)
              local res = proxy_client:send {
                path    = "/tls-buffered-proxying",
                headers = {
                  ["Host"] = "example.com",
                }
              }

              return pcall(function()
                 body = assert.res_status(502, res)
                 assert(proxy_client:close())
              end)
            end, 10)
            assert.matches("An invalid response was received from the upstream server", body)
          end
        end)

        it("request is allowed through if depth limit is sufficient", function()
          local service_tls_id
          if subsystems == "http" then
            service_tls_id = service_tls.id
          else
            service_tls_id = tls_service_tls.id
          end
          local res = assert(admin_client:patch("/services/" .. service_tls_id, {
            body = {
              tls_verify_depth = 1,
            },
            headers = { ["Content-Type"] = "application/json" },
          }))

          assert.res_status(200, res)

          wait_for_all_config_update(subsystems)

          local body
          helpers.wait_until(function()
            local proxy_client = get_proxy_client(subsystems, 19001)
            local path
            if subsystems == "http" then
              path = "/tls"
            else
              path = "/"
            end
            res = assert(proxy_client:send {
              path    = path,
              headers = {
                ["Host"] = "example.com",
              }
            })

            return pcall(function()
              body = assert.res_status(200, res)
              assert(proxy_client:close())
            end)
          end, 10)

          assert.equals("it works", body)

          -- buffered_proxying
          if subsystems == "http" then
            helpers.wait_until(function()
              local proxy_client = get_proxy_client(subsystems, 19001)
              local path = "/tls-buffered-proxying"
              res = assert(proxy_client:send {
                path    = path,
                headers = {
                  ["Host"] = "example.com",
                }
              })

              return pcall(function()
                body = assert.res_status(200, res)
                assert(proxy_client:close())
              end)
            end, 10)

            assert.equals("it works", body)
          end
        end)
      end)
    end)
  end
  end)
end
end   -- for flavor
