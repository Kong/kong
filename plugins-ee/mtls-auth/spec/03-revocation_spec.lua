-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local pl_file = require "pl.file"
local cjson   = require "cjson"
local fmt     = string.format
local http_mock = require "spec.helpers.http_mock"

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local CA = pl_file.read(helpers.get_fixtures_path() .. "/ocsp-responder-docker/certificates/ca.pem")
local SUBCA = pl_file.read(helpers.get_fixtures_path() .. "/ocsp-responder-docker/certificates/intermediate.pem")

local HTTP_SERVER_PORT = helpers.get_available_port()

local SQUID_HOST = os.getenv("KONG_SPEC_TEST_SQUIDCUSTOM_HOST") or "squidcustom"
local SQUID_PORT = tonumber(os.getenv("KONG_SPEC_TEST_SQUIDCUSTOM_PORT_3128")) or 3128

local OCSPSERVER_HOST = os.getenv("KONG_SPEC_TEST_OCSPSERVER_HOST") or "ocspserver"

--[[
What does pongo do in .pongo/ocspserver.yml:
cd plugins-ee/mtls-auth/spec/fixtures/ocsp-responder-docker
docker build -t ocsp-responder-docker .
docker run -it -p2560:2560 -p8080:8080 --rm -v (pwd)/certificates:/data ocsp-responder-docker
<Ctrl+C to stop the container>
]]--

for _, strategy in strategies() do
  describe("Plugin: mtls-auth (revocation) [#" .. strategy .. "]", function()
    local mtls_client
    local bp, db
    local service
    local ca_cert, sub_ca_cert
    local db_strategy = strategy ~= "off" and strategy or nil
    local mock

    local function delete_cache()
      local admin_client = helpers.admin_client()
      local res = assert(admin_client:send({
        method  = "DELETE",
        path    = "/cache",
      }))
      assert.res_status(204, res)
      admin_client:close()
    end

    lazy_setup(function()
      bp, db = helpers.get_db_utils(db_strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "ca_certificates",
        "mtls_auth_credentials",
      }, { "mtls-auth", })

      bp.consumers:insert {
        username = "ocsp-valid@konghq.com"
      }

      bp.consumers:insert {
        username = "ocsp-revoked@konghq.com"
      }

      bp.consumers:insert {
        username = "crl-valid@konghq.com"
      }

      bp.consumers:insert {
        username = "crl-revoked@konghq.com"
      }

      service = bp.services:insert{
        protocol = "https",
        port     = helpers.mock_upstream_ssl_port,
        host     = helpers.mock_upstream_ssl_host,
      }

      local route_no_proxy_strict = bp.routes:insert {
        hosts   = { "noproxy-strict.test" },
        service = { id = service.id, },
      }

      local route_proxy_strict = bp.routes:insert {
        hosts   = { "proxy-strict.test" },
        service = { id = service.id, },
      }

      local route_bad_proxy_strict = bp.routes:insert {
        hosts   = { "badproxy-strict.test" },
        service = { id = service.id, },
      }

      local route_no_proxy_skip = bp.routes:insert {
        hosts   = { "noproxy-skip.test" },
        service = { id = service.id, },
      }

      local route_bad_proxy_ignore = bp.routes:insert {
        hosts   = { "badproxy-ignore.test" },
        service = { id = service.id, },
      }

      ca_cert = assert(db.ca_certificates:insert({
        cert = CA,
      }))

      sub_ca_cert = assert(db.ca_certificates:insert({
        cert = SUBCA,
      }))

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route_no_proxy_strict.id },
        config = {
          ca_certificates = { ca_cert.id, sub_ca_cert.id},
          revocation_check_mode = "STRICT",
          cert_cache_ttl = 0,
          cache_ttl = 0,
        },
      })

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route_proxy_strict.id },
        config = {
          ca_certificates = { ca_cert.id, sub_ca_cert.id},
          revocation_check_mode = "STRICT",
          http_proxy_host = SQUID_HOST,
          http_proxy_port = SQUID_PORT,
          cert_cache_ttl = 0,
          cache_ttl = 0,
        },
      })

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route_bad_proxy_strict.id },
        config = {
          ca_certificates = { ca_cert.id, sub_ca_cert.id},
          revocation_check_mode = "STRICT",
          http_proxy_host = SQUID_HOST,
          http_proxy_port = 3129, -- this port is not open so HTTP CONNECT will fail
          cert_cache_ttl = 0,
          cache_ttl = 0,
        },
      })

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route_no_proxy_skip.id },
        config = {
          ca_certificates = { ca_cert.id, sub_ca_cert.id},
          revocation_check_mode = "SKIP",
          cert_cache_ttl = 0,
          cache_ttl = 0,
        },
      })

      assert(bp.plugins:insert {
        name = "mtls-auth",
        route = { id = route_bad_proxy_ignore.id },
        config = {
          ca_certificates = { ca_cert.id, sub_ca_cert.id},
          revocation_check_mode = "IGNORE_CA_ERROR",
          http_proxy_host = SQUID_HOST,
          http_proxy_port = 3129, -- this port is not open so HTTP CONNECT will fail
          cert_cache_ttl = 0,
          cache_ttl = 0,
        },
      })

      local format = [[
      proxy_ssl_certificate ]] .. helpers.get_fixtures_path() .. [[/ocsp-responder-docker/certificates/%s.pem;
      proxy_ssl_certificate_key ]] .. helpers.get_fixtures_path() .. [[/ocsp-responder-docker/certificates/%s.pem.key;
      proxy_ssl_name %s.test;
      proxy_ssl_server_name on;
      proxy_set_header Host %s.test;
      proxy_pass https://127.0.0.1:9443/get;
      ]]
      mock = http_mock.new(HTTP_SERVER_PORT, {
        ["/no_proxy_strict_ocsp_valid"] = {
          directives = fmt(format, "ocsp-valid", "ocsp-valid", "noproxy-strict", "noproxy-strict"),
        },
        ["/no_proxy_strict_ocsp_valid_inter"] = {
          directives = fmt(format, "ocsp-valid-inter", "ocsp-valid", "noproxy-strict", "noproxy-strict"),
        },
        ["/no_proxy_strict_ocsp_revoked"] = {
          directives = fmt(format, "ocsp-revoked", "ocsp-revoked", "noproxy-strict", "noproxy-strict"),
        },
        ["/no_proxy_strict_ocsp_revoked_inter"] = {
          directives = fmt(format, "ocsp-revoked-inter", "ocsp-revoked", "noproxy-strict", "noproxy-strict"),
        },
        ["/no_proxy_strict_crl_valid"] = {
          directives = fmt(format, "crl-valid", "crl-valid", "noproxy-strict", "noproxy-strict"),
        },
        ["/no_proxy_strict_crl_valid_inter"] = {
          directives = fmt(format, "crl-valid-inter", "crl-valid", "noproxy-strict", "noproxy-strict"),
        },
        ["/no_proxy_strict_crl_revoked"] = {
          directives = fmt(format, "crl-revoked", "crl-revoked", "noproxy-strict", "noproxy-strict"),
        },
        ["/no_proxy_strict_crl_revoked_inter"] = {
          directives = fmt(format, "crl-revoked-inter", "crl-revoked", "noproxy-strict", "noproxy-strict"),
        },
        ["/no_proxy_skip_ocsp_valid_inter"] = {
          directives = fmt(format, "ocsp-valid-inter", "ocsp-valid", "noproxy-skip", "noproxy-skip"),
        },
        ["/no_proxy_skip_ocsp_revoked_inter"] = {
          directives = fmt(format, "ocsp-revoked-inter", "ocsp-revoked", "noproxy-skip", "noproxy-skip"),
        },
        ["/no_proxy_skip_crl_valid_inter"] = {
          directives = fmt(format, "crl-valid-inter", "crl-valid", "noproxy-skip", "noproxy-skip"),
        },
        ["/no_proxy_skip_crl_revoked_inter"] = {
          directives = fmt(format, "crl-revoked-inter", "crl-revoked", "noproxy-skip", "noproxy-skip"),
        },
        ["/proxy_strict_ocsp_valid_inter"] = {
          directives = fmt(format, "ocsp-valid-inter", "ocsp-valid", "proxy-strict", "proxy-strict"),
        },
        ["/proxy_strict_ocsp_revoked_inter"] = {
          directives = fmt(format, "ocsp-revoked-inter", "ocsp-revoked", "proxy-strict", "proxy-strict"),
        },
        ["/proxy_strict_crl_valid_inter"] = {
          directives = fmt(format, "crl-valid-inter", "crl-valid", "proxy-strict", "proxy-strict"),
        },
        ["/proxy_strict_crl_revoked_inter"] = {
          directives = fmt(format, "crl-revoked-inter", "crl-revoked", "proxy-strict", "proxy-strict"),
        },
        ["/bad_proxy_strict_ocsp_valid_inter"] = {
          directives = fmt(format, "ocsp-valid-inter", "ocsp-valid", "badproxy-strict", "badproxy-strict"),
        },
        ["/bad_proxy_strict_ocsp_revoked_inter"] = {
          directives = fmt(format, "ocsp-revoked-inter", "ocsp-revoked", "badproxy-strict", "badproxy-strict"),
        },
        ["/bad_proxy_strict_crl_valid_inter"] = {
          directives = fmt(format, "crl-valid-inter", "crl-valid", "badproxy-strict", "badproxy-strict"),
        },
        ["/bad_proxy_strict_crl_revoked_inter"] = {
          directives = fmt(format, "crl-revoked-inter", "crl-revoked", "badproxy-strict", "badproxy-strict"),
        },
        ["/bad_proxy_ignore_ocsp_valid_inter"] = {
          directives = fmt(format, "ocsp-valid-inter", "ocsp-valid", "badproxy-ignore", "badproxy-ignore"),
        },
        ["/bad_proxy_ignore_ocsp_revoked_inter"] = {
          directives = fmt(format, "ocsp-revoked-inter", "ocsp-revoked", "badproxy-ignore", "badproxy-ignore"),
        },
        ["/bad_proxy_ignore_crl_valid_inter"] = {
          directives = fmt(format, "crl-valid-inter", "crl-valid", "badproxy-ignore", "badproxy-ignore"),
        },
        ["/bad_proxy_ignore_crl_revoked_inter"] = {
          directives = fmt(format, "crl-revoked-inter", "crl-revoked", "badproxy-ignore", "badproxy-ignore"),
        },
      }, {
        hostname = "mtls_test_client",
      })
      assert(mock:start())

      local fixtures = {
        dns_mock = helpers.dns_mock.new(),
      }

      if OCSPSERVER_HOST ~= "ocspserver" then
        -- dns mock needed to always redirect advertised host
        fixtures.dns_mock:A {
          name = "ocspserver",
          address = OCSPSERVER_HOST,
        }
      end

      assert(helpers.start_kong({
        database   = db_strategy,
        plugins = "bundled,mtls-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      mock:stop()
    end)

    before_each(function()
      helpers.clean_logfile() -- prevent log assertions from poisoning each other.
    end)

    -- leaf_only = true means the client only sends the client leaf cert
    -- leaf_only = false means the client sends the client leaf cert and the intermediate ca cert
    local test_cases = {                                                                     -- no_proxy    proxy       bad_proxy
      {cert = "valid",   type = "ocsp", leaf_only = true,  mode = "strict", suffix = "",        res1 = 200,                                            },
      {cert = "valid",   type = "ocsp", leaf_only = false, mode = "strict", suffix = "_inter",  res1 = 200, res2 = 200, res3 = 401, test_cache = true, },
      {cert = "valid",   type = "ocsp", leaf_only = false, mode = "ignore", suffix = "_inter",                          res3 = 200,                    },
      {cert = "valid",   type = "ocsp", leaf_only = false, mode = "skip",   suffix = "_inter",  res1 = 200,                                            },
      {cert = "valid",   type = "crl",  leaf_only = true,  mode = "strict", suffix = "",        res1 = 200,                                            },
      {cert = "valid",   type = "crl",  leaf_only = false, mode = "strict", suffix = "_inter",  res1 = 200, res2 = 200, res3 = 401, test_cache = true, },
      {cert = "valid",   type = "crl",  leaf_only = false, mode = "ignore", suffix = "_inter",                          res3 = 200,                    },
      {cert = "valid",   type = "crl",  leaf_only = false, mode = "skip",   suffix = "_inter",  res1 = 200,                                            },
      {cert = "revoked", type = "ocsp", leaf_only = true,  mode = "strict", suffix = "",        res1 = 401,                                            },
      {cert = "revoked", type = "ocsp", leaf_only = false, mode = "strict", suffix = "_inter",  res1 = 401, res2 = 401, res3 = 401, test_cache = true, },
      {cert = "revoked", type = "ocsp", leaf_only = false, mode = "ignore", suffix = "_inter",                          res3 = 200,                    },
      {cert = "revoked", type = "ocsp", leaf_only = false, mode = "skip",   suffix = "_inter",  res1 = 200,                                            },
      {cert = "revoked", type = "crl",  leaf_only = true,  mode = "strict", suffix = "",        res1 = 401,                                            },
      {cert = "revoked", type = "crl",  leaf_only = false, mode = "strict", suffix = "_inter",  res1 = 401, res2 = 401, res3 = 401, test_cache = true, },
      {cert = "revoked", type = "crl",  leaf_only = false, mode = "ignore", suffix = "_inter",                          res3 = 200,                    },
      {cert = "revoked", type = "crl",  leaf_only = false, mode = "skip",   suffix = "_inter",  res1 = 200,                                            },
    }

    for _, case in ipairs(test_cases) do
      local cert = case.cert
      local case_type = case.type
      local leaf_only = case.leaf_only
      local mode = case.mode
      local name = case_type .. "-" .. cert
      local suffix = case.suffix
      local res1 = case.res1
      local res2 = case.res2
      local res3 = case.res3
      local test_cache = case.test_cache

      if res1 then
        local url = fmt("/no_proxy_%s_%s_%s%s", mode, case_type, cert, suffix)

        it(fmt("returns HTTP %s on https request if %s certificate passed with no proxy (%s, leaf_only = %s, mode = %s), cache miss for revocation status",
              res1, cert, case_type, leaf_only, mode), function()
          delete_cache()
          mtls_client = mock:get_client()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = url,
          })
          local body = assert.res_status(res1, res)
          mtls_client:close()
          mock.client = nil
          local json = cjson.decode(body)
          if res1 == 200 then
            assert.equal(name .. "@konghq.com", json.headers["x-consumer-username"])
          else
            assert.equal("TLS certificate failed verification", json.message)
          end
          if mode ~= "skip" then
            assert.logfile().has.line('cache miss for revocation status', true)
          end
        end)

        if test_cache then
          it(fmt("returns HTTP %s on https request if %s certificate passed with no proxy (%s, leaf_only = %s, mode = %s), cache hit for revocation status",
                res1, cert, case_type, leaf_only, mode), function()
            mtls_client = mock:get_client()
            local res = assert(mtls_client:send {
              method  = "GET",
              path    = url,
            })
            local body = assert.res_status(res1, res)
            mtls_client:close()
            mock.client = nil
            local json = cjson.decode(body)
            if res1 == 200 then
              assert.equal(name .. "@konghq.com", json.headers["x-consumer-username"])
            else
              assert.equal("TLS certificate failed verification", json.message)
            end
            if mode ~= "skip" then
              assert.logfile().has.no.line('cache miss for revocation status', true)
            end
          end)
        end
      end

      if res2 then
        local url = fmt("/proxy_%s_%s_%s%s", mode, case_type, cert, suffix)

        it(fmt("returns HTTP %s on https request if %s certificate passed with proxy (%s, leaf_only = %s, mode = %s), cache miss for revocation status",
              res2, cert, case_type, leaf_only, mode), function()
          delete_cache()
          mtls_client = mock:get_client()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = url,
          })
          local body = assert.res_status(res2, res)
          mtls_client:close()
          mock.client = nil
          local json = cjson.decode(body)
          if res2 == 200 then
            assert.equal(name .. "@konghq.com", json.headers["x-consumer-username"])
          else
            assert.equal("TLS certificate failed verification", json.message)
          end
          if mode ~= "skip" then
            assert.logfile().has.line('cache miss for revocation status', true)
          end
        end)
      end

      if res3 then
        local url = fmt("/bad_proxy_%s_%s_%s%s", mode, case_type, cert, suffix)

        it(fmt("returns HTTP %s on https request if %s certificate passed with bad proxy (%s, leaf_only = %s, mode = %s), cache miss for revocation status",
              res3, cert, case_type, leaf_only, mode), function()
          delete_cache()
          mtls_client = mock:get_client()
          local res = assert(mtls_client:send {
            method  = "GET",
            path    = url,
          })
          local body = assert.res_status(res3, res)
          mtls_client:close()
          mock.client = nil
          local json = cjson.decode(body)
          if res3 == 200 then
            assert.equal(name .. "@konghq.com", json.headers["x-consumer-username"])
          else
            assert.equal("TLS certificate failed verification", json.message)
          end
          if mode ~= "skip" then
            assert.logfile().has.line('cache miss for revocation status', true)
          end
        end)

        if test_cache then
          it(fmt("returns HTTP %s on https request if %s certificate passed with bad proxy (%s, leaf_only = %s, mode = %s), cache will not be stored for communication failure",
                res3, cert, case_type, leaf_only, mode), function()
            mtls_client = mock:get_client()
            local res = assert(mtls_client:send {
              method  = "GET",
              path    = url,
            })
            local body = assert.res_status(res3, res)
            mtls_client:close()
            mock.client = nil
            local json = cjson.decode(body)
            if res3 == 200 then
              assert.equal(name .. "@konghq.com", json.headers["x-consumer-username"])
            else
              assert.equal("TLS certificate failed verification", json.message)
            end
            if mode ~= "skip" then
              assert.logfile().has.line('cache miss for revocation status', true)
            end
          end)
        end
      end
    end
  end)
end
