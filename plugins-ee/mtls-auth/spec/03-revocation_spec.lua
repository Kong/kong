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

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

local CA = pl_file.read("/kong-plugin/spec/fixtures/ocsp-responder-docker/certificates/ca.pem")
local SUBCA = pl_file.read("/kong-plugin/spec/fixtures/ocsp-responder-docker/certificates/intermediate.pem")

--[[
What does pongo do in .pongo/ocspserver.yml:
cd plugins-ee/mtls-auth/spec/fixtures/ocsp-responder-docker
docker build -t ocsp-responder-docker .
docker run -it -p2560:2560 -p8080:8080 --rm -v (pwd)/certificates:/data ocsp-responder-docker
<Ctrl+C to stop the container>
]]--

for _, strategy in strategies() do
  -- leaf_only = true means the client only sends the client leaf cert
  -- leaf_only = false means the client sends the client leaf cert and the intermediate ca cert
  local test_cases = {
    {cert = "valid",   type = "ocsp", leaf_only = true,  mode = "STRICT",          suffix = "",        res1 = 200, res2 = 200, res3 = 401, },
    {cert = "valid",   type = "ocsp", leaf_only = true,  mode = "IGNORE_CA_ERROR", suffix = "",        res1 = 200, res2 = 200, res3 = 200, },
    {cert = "valid",   type = "ocsp", leaf_only = true,  mode = "SKIP",            suffix = "",        res1 = 200, res2 = 200, res3 = 200, },
    {cert = "valid",   type = "ocsp", leaf_only = false, mode = "STRICT",          suffix = "-inter",  res1 = 200, res2 = 200, res3 = 401, },
    {cert = "valid",   type = "ocsp", leaf_only = false, mode = "IGNORE_CA_ERROR", suffix = "-inter",  res1 = 200, res2 = 200, res3 = 200, },
    {cert = "valid",   type = "ocsp", leaf_only = false, mode = "SKIP",            suffix = "-inter",  res1 = 200, res2 = 200, res3 = 200, },
    {cert = "valid",   type = "crl",  leaf_only = true,  mode = "STRICT",          suffix = "",        res1 = 200, res2 = 200, res3 = 401, },
    {cert = "valid",   type = "crl",  leaf_only = true,  mode = "IGNORE_CA_ERROR", suffix = "",        res1 = 200, res2 = 200, res3 = 200, },
    {cert = "valid",   type = "crl",  leaf_only = true,  mode = "SKIP",            suffix = "",        res1 = 200, res2 = 200, res3 = 200, },
    {cert = "valid",   type = "crl",  leaf_only = false, mode = "STRICT",          suffix = "-inter",  res1 = 200, res2 = 200, res3 = 401, },
    {cert = "valid",   type = "crl",  leaf_only = false, mode = "IGNORE_CA_ERROR", suffix = "-inter",  res1 = 200, res2 = 200, res3 = 200, },
    {cert = "valid",   type = "crl",  leaf_only = false, mode = "SKIP",            suffix = "-inter",  res1 = 200, res2 = 200, res3 = 200, },
    {cert = "revoked", type = "ocsp", leaf_only = true,  mode = "STRICT",          suffix = "",        res1 = 401, res2 = 401, res3 = 401, },
    {cert = "revoked", type = "ocsp", leaf_only = true,  mode = "IGNORE_CA_ERROR", suffix = "",        res1 = 401, res2 = 401, res3 = 200, },
    {cert = "revoked", type = "ocsp", leaf_only = true,  mode = "SKIP",            suffix = "",        res1 = 200, res2 = 200, res3 = 200, },
    {cert = "revoked", type = "ocsp", leaf_only = false, mode = "STRICT",          suffix = "-inter",  res1 = 401, res2 = 401, res3 = 401, },
    {cert = "revoked", type = "ocsp", leaf_only = false, mode = "IGNORE_CA_ERROR", suffix = "-inter",  res1 = 401, res2 = 401, res3 = 200, },
    {cert = "revoked", type = "ocsp", leaf_only = false, mode = "SKIP",            suffix = "-inter",  res1 = 200, res2 = 200, res3 = 200, },
    {cert = "revoked", type = "crl",  leaf_only = true,  mode = "STRICT",          suffix = "",        res1 = 401, res2 = 401, res3 = 401, },
    {cert = "revoked", type = "crl",  leaf_only = true,  mode = "IGNORE_CA_ERROR", suffix = "",        res1 = 401, res2 = 401, res3 = 200, },
    {cert = "revoked", type = "crl",  leaf_only = true,  mode = "SKIP",            suffix = "",        res1 = 200, res2 = 200, res3 = 200, },
    {cert = "revoked", type = "crl",  leaf_only = false, mode = "STRICT",          suffix = "-inter",  res1 = 401, res2 = 401, res3 = 401, },
    {cert = "revoked", type = "crl",  leaf_only = false, mode = "IGNORE_CA_ERROR", suffix = "-inter",  res1 = 401, res2 = 401, res3 = 200, },
    {cert = "revoked", type = "crl",  leaf_only = false, mode = "SKIP",            suffix = "-inter",  res1 = 200, res2 = 200, res3 = 200, },
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
    local mtls_fixtures = { http_mock = {
      mtls_server_block = [[
        server {
            server_name mtls_test_client;
            listen 10121;

            location = /no_proxy {
              proxy_ssl_certificate ../spec/fixtures/ocsp-responder-docker/certificates/]] .. name .. suffix .. [[.pem;
              proxy_ssl_certificate_key ../spec/fixtures/ocsp-responder-docker/certificates/]] .. name .. [[.pem.key;
              proxy_ssl_name example.com;
              # enable send the SNI sent to server
              proxy_ssl_server_name on;
              proxy_set_header Host example.com;

              proxy_pass https://127.0.0.1:9443/get;
            }

            location = /proxy {
              proxy_ssl_certificate ../spec/fixtures/ocsp-responder-docker/certificates/]] .. name .. "2" .. suffix .. [[.pem;
              proxy_ssl_certificate_key ../spec/fixtures/ocsp-responder-docker/certificates/]] .. name .. [[2.pem.key;
              proxy_ssl_name exampleproxy.com;
              # enable send the SNI sent to server
              proxy_ssl_server_name on;
              proxy_set_header Host exampleproxy.com;

              proxy_pass https://127.0.0.1:9443/get;
            }

            location = /bad_proxy {
              # We use a second valid certificate here to defeat the DN -> Consumer cache
              proxy_ssl_certificate ../spec/fixtures/ocsp-responder-docker/certificates/]] .. name .. "3" .. suffix .. [[.pem;
              proxy_ssl_certificate_key ../spec/fixtures/ocsp-responder-docker/certificates/]] .. name .. [[3.pem.key;
              proxy_ssl_name examplebadproxy.com;
              # enable send the SNI sent to server
              proxy_ssl_server_name on;
              proxy_set_header Host examplebadproxy.com;

              proxy_pass https://127.0.0.1:9443/get;
            }
        }
      ]], }
    }

    describe("#flaky Plugin: mtls-auth (revocation) [#" .. strategy .. "]", function()
      local mtls_client
      local bp, db
      local consumer, consumer2, consumer3, service, route
      local ca_cert, sub_ca_cert
      local db_strategy = strategy ~= "off" and strategy or nil

      lazy_setup(function()
        bp, db = helpers.get_db_utils(db_strategy, {
          "routes",
          "services",
          "plugins",
          "consumers",
          "ca_certificates",
          "mtls_auth_credentials",
        }, { "mtls-auth", })

        consumer = bp.consumers:insert {
          username = name .. "@konghq.com"
        }

        consumer2 = bp.consumers:insert {
          username = name .. "2@konghq.com"
        }

        consumer3 = bp.consumers:insert {
          username = name .. "3@konghq.com"
        }

        service = bp.services:insert{
          protocol = "https",
          port     = helpers.mock_upstream_ssl_port,
          host     = helpers.mock_upstream_ssl_host,
        }

        route = bp.routes:insert {
          hosts   = { "example.com" },
          service = { id = service.id, },
        }

        local route_proxy = bp.routes:insert {
          hosts   = { "exampleproxy.com" },
          service = { id = service.id, },
        }

        local route_bad_proxy = bp.routes:insert {
          hosts   = { "examplebadproxy.com" },
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
          route = { id = route.id },
          config = {
            ca_certificates = { ca_cert.id, sub_ca_cert.id},
            revocation_check_mode = mode,
            cert_cache_ttl = 0,
            cache_ttl = 0,
          },
        })

        assert(bp.plugins:insert {
          name = "mtls-auth",
          route = { id = route_proxy.id },
          config = {
            ca_certificates = { ca_cert.id, sub_ca_cert.id},
            revocation_check_mode = mode,
            http_proxy_host = "squidcustom",
            http_proxy_port = 3128,
            cert_cache_ttl = 0,
            cache_ttl = 0,
          },
        })

        assert(bp.plugins:insert {
          name = "mtls-auth",
          route = { id = route_bad_proxy.id },
          config = {
            ca_certificates = { ca_cert.id, sub_ca_cert.id},
            revocation_check_mode = mode,
            http_proxy_host = "squidcustom",
            http_proxy_port = 3129, -- this port is not open so HTTP CONNECT will fail
            cert_cache_ttl = 0,
            cache_ttl = 0,
          },
        })

        assert(helpers.start_kong({
          database   = db_strategy,
          plugins = "bundled,mtls-auth",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }, nil, nil, mtls_fixtures))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        helpers.clean_logfile() -- prevent log assertions from poisoning each other.
      end)

      it(fmt("returns HTTP %s on https request if %s certificate passed with no proxy (%s, leaf_only = %s, mode = %s), cache miss for revocation status",
            res1, cert, case_type, leaf_only, mode), function()
        mtls_client = helpers.http_client("127.0.0.1", 10121)
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/no_proxy",
        })
        local body = assert.res_status(res1, res)
        mtls_client:close()
        local json = cjson.decode(body)
        if res1 == 200 then
          assert.equal(name .. "@konghq.com", json.headers["x-consumer-username"])
          assert.equal(consumer.id, json.headers["x-consumer-id"])
        else
          assert.equal("TLS certificate failed verification", json.message)
        end
        if mode ~= "SKIP" then
          assert.logfile().has.line('cache miss for revocation status', true)
        end
      end)

      it(fmt("returns HTTP %s on https request if %s certificate passed with no proxy (%s, leaf_only = %s, mode = %s), cache hit for revocation status",
            res1, cert, case_type, leaf_only, mode), function()
        mtls_client = helpers.http_client("127.0.0.1", 10121)
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/no_proxy",
        })
        local body = assert.res_status(res1, res)
        mtls_client:close()
        local json = cjson.decode(body)
        if res1 == 200 then
          assert.equal(name .. "@konghq.com", json.headers["x-consumer-username"])
          assert.equal(consumer.id, json.headers["x-consumer-id"])
        else
          assert.equal("TLS certificate failed verification", json.message)
        end
        if mode ~= "SKIP" then
          assert.logfile().has.no.line('cache miss for revocation status', true)
        end
      end)

      it(fmt("returns HTTP %s on https request if %s certificate passed with proxy (%s, leaf_only = %s, mode = %s), cache miss for revocation status",
            res2, cert, case_type, leaf_only, mode), function()
        mtls_client = helpers.http_client("127.0.0.1", 10121)
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/proxy",
        })
        local body = assert.res_status(res2, res)
        mtls_client:close()
        local json = cjson.decode(body)
        if res2 == 200 then
          assert.equal(name .. "2@konghq.com", json.headers["x-consumer-username"])
          assert.equal(consumer2.id, json.headers["x-consumer-id"])
        else
          assert.equal("TLS certificate failed verification", json.message)
        end
        if mode ~= "SKIP" then
          assert.logfile().has.line('cache miss for revocation status', true)
        end
      end)

      it(fmt("returns HTTP %s on https request if %s certificate passed with proxy (%s, leaf_only = %s, mode = %s), cache hit for revocation status",
            res2, cert, case_type, leaf_only, mode), function()
        mtls_client = helpers.http_client("127.0.0.1", 10121)
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/proxy",
        })
        local body = assert.res_status(res2, res)
        mtls_client:close()
        local json = cjson.decode(body)
        if res2 == 200 then
          assert.equal(name .. "2@konghq.com", json.headers["x-consumer-username"])
          assert.equal(consumer2.id, json.headers["x-consumer-id"])
        else
          assert.equal("TLS certificate failed verification", json.message)
        end
        if mode ~= "SKIP" then
          assert.logfile().has.no.line('cache miss for revocation status', true)
        end
      end)

      it(fmt("returns HTTP %s on https request if %s certificate passed with bad proxy (%s, leaf_only = %s, mode = %s), cache miss for revocation status",
            res3, cert, case_type, leaf_only, mode), function()
        mtls_client = helpers.http_client("127.0.0.1", 10121)
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/bad_proxy",
        })
        local body = assert.res_status(res3, res)
        mtls_client:close()
        local json = cjson.decode(body)
        if res3 == 200 then
          assert.equal(name .. "3@konghq.com", json.headers["x-consumer-username"])
          assert.equal(consumer3.id, json.headers["x-consumer-id"])
        else
          assert.equal("TLS certificate failed verification", json.message)
        end
        if mode ~= "SKIP" then
          assert.logfile().has.line('cache miss for revocation status', true)
        end
      end)

      it(fmt("returns HTTP %s on https request if %s certificate passed with bad proxy (%s, leaf_only = %s, mode = %s), cache hit for revocation status",
            res3, cert, case_type, leaf_only, mode), function()
        mtls_client = helpers.http_client("127.0.0.1", 10121)
        local res = assert(mtls_client:send {
          method  = "GET",
          path    = "/bad_proxy",
        })
        local body = assert.res_status(res3, res)
        mtls_client:close()
        local json = cjson.decode(body)
        if res3 == 200 then
          assert.equal(name .. "3@konghq.com", json.headers["x-consumer-username"])
          assert.equal(consumer3.id, json.headers["x-consumer-id"])
        else
          assert.equal("TLS certificate failed verification", json.message)
        end
        if mode ~= "SKIP" then
          assert.logfile().has.no.line('cache miss for revocation status', true)
        end
      end)
    end)
  end
end
