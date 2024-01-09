-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers      = require "spec.helpers"
local ssl_fixtures = require "spec.fixtures.ssl"
local pl_path      = require "pl.path"
local pl_file      = require "pl.file"
local cjson        = require "cjson"

local prefix = helpers.test_conf.prefix

local function log_match(fname, str)
  local path = pl_path.join(prefix, "logs", fname)

  return function()
    local _, contents = pcall(pl_file.read, path)
    return contents and ngx.re.find(contents, str, "oji")
  end
end

local fixtures_path = helpers.get_fixtures_path()

local fixtures = {
  dns_mock = helpers.dns_mock.new(),
  stream_mock = {
    forward_proxy = [[
    server {
      listen 16797;
      error_log logs/proxy.log debug;

      content_by_lua_block {
        require("spec.fixtures.forward-proxy-server").connect()
      }
    }

    ]],
  },

  http_mock = {
    upstreams_mtls = string.format([[
      server {
          server_name example.com;
          listen 16798 ssl;

          ssl_certificate        ]] .. fixtures_path .. [[/mtls_certs/example.com.crt;
          ssl_certificate_key    ]] .. fixtures_path .. [[/mtls_certs/example.com.key;
          ssl_client_certificate ]] .. fixtures_path .. [[/mtls_certs/ca.crt;
          ssl_verify_client      on;
          ssl_session_tickets    off;
          ssl_session_cache      off;
          keepalive_requests     0;

          location = / {
              echo 'it works';
          }

          location = /408 {
              return 408 "408";
          }
      }
    ]], prefix, prefix, prefix),
  },
}

fixtures.dns_mock:A {
  name = "proxy.test",
  address = "127.0.0.1",
}

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe("forward-proxy #" .. strategy, function()
    local proxy_client_ssl, proxy_client
    local params = { headers = { host = "proxy.test" } }

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "certificates",
        "ca_certificates",
        "upstreams",
        "targets",
      }, {
        "forward-proxy",
      })

      local mtls = bp.services:insert {
        url                = "https://127.0.0.1:16798/",
        client_certificate = bp.certificates:insert {
          cert = ssl_fixtures.cert_client,
          key  = ssl_fixtures.key_client,
        }
      }

      bp.plugins:insert {
        name   = "forward-proxy",
        config = {
          https_proxy_host = "127.0.0.1",
          https_proxy_port = 16797,
        },
        route = bp.routes:insert {
          hosts   = { "proxy.test" },
          paths   = { "/https-with-https-config" },
          service = mtls,
        },
      }

      bp.plugins:insert {
        name   = "forward-proxy",
        config = {
          http_proxy_host = "127.0.0.1",
          http_proxy_port = 16797,
        },
        route = bp.routes:insert {
          hosts   = { "proxy.test" },
          paths   = { "/https-with-http-config" },
          service = mtls,
        },
      }

      bp.plugins:insert {
        name   = "forward-proxy",
        config = {
          http_proxy_host = "1.1.1.1", -- should not be used
          http_proxy_port = 999,
          https_proxy_host = "127.0.0.1",
          https_proxy_port = 16797,
        },
        route = bp.routes:insert {
          hosts   = { "proxy.test" },
          paths   = { "/https-with-full-config" },
          service = mtls,
        },
      }

      local service = assert(bp.services:insert {
        url = "http://example.com/",
      })

      bp.plugins:insert {
        route = bp.routes:insert {
          service   = service,
          paths     = { "/http-with-http-config" },
        },
        name   = "forward-proxy",
        config = {
          http_proxy_host = helpers.mock_upstream_host,
          http_proxy_port = helpers.mock_upstream_port,
        },
      }

      bp.plugins:insert {
        route = bp.routes:insert {
          service   = service,
          paths     = { "/http-with-https-config" },
        },
        name   = "forward-proxy",
        config = {
          https_proxy_host = helpers.mock_upstream_host,
          https_proxy_port = helpers.mock_upstream_port,
        },
      }

      bp.plugins:insert {
        route = bp.routes:insert {
          service   = service,
          paths     = { "/http-with-full-config" },
        },
        name   = "forward-proxy",
        config = {
          http_proxy_host = helpers.mock_upstream_host,
          http_proxy_port = helpers.mock_upstream_port,
          https_proxy_host = '1.1.1.1', -- should not be used
          https_proxy_port = 999,
        },
      }

      assert(helpers.start_kong({
        database   = strategy,
        plugins = "forward-proxy",
        nginx_conf = "spec/fixtures/custom_nginx.template",

        -- this is unused, but required for the the template to include a stream {} block
        stream_listen = "0.0.0.0:5555",
      }, nil, nil, fixtures))

      proxy_client_ssl = assert(helpers.proxy_ssl_client(1000, "proxy.test"))
      proxy_client = assert(helpers.proxy_client())
    end)

    lazy_teardown(function()
      if proxy_client_ssl then
        proxy_client_ssl:close()
      end
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong(nil, true)

    end)

    describe("Scheme", function()

      after_each(function()
        local path = pl_path.join(prefix, "logs", "proxy.log")
        helpers.clean_logfile(path)
      end)

      it("https works with https config set", function()
        local res = proxy_client_ssl:get("/https-with-https-config", params)

        local body = assert.res_status(200, res)
        assert.equals("it works", body)

        helpers.wait_until(log_match("proxy.log", "CONNECT 127.0.0.1:16798"), 5)
      end)

      it("https works with http config set (fallback)", function()
        local res = proxy_client_ssl:get("/https-with-http-config", params)

        local body = assert.res_status(200, res)
        assert.equals("it works", body)

        helpers.wait_until(log_match("proxy.log", "CONNECT 127.0.0.1:16798"), 5)
      end)

      it("https works and the http config doesn't override it", function()
        local res = proxy_client_ssl:get("/https-with-full-config", params)

        local body = assert.res_status(200, res)
        assert.equals("it works", body)

        helpers.wait_until(log_match("proxy.log", "CONNECT 127.0.0.1:16798"), 5)
      end)

      it("http works with http config set", function()
        local res = proxy_client:get("/http-with-http-config", params)
  
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.matches("lua-resty-http", json.headers["user-agent"], nil, true)
      end)
  
      it("http works with https config set (fallback)", function()
        local res = proxy_client:get("/http-with-https-config", params)
  
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.matches("lua-resty-http", json.headers["user-agent"], nil, true)
      end)

      it("http works and the https config doesn't override it", function()
        local res = proxy_client:get("/http-with-full-config", params)
  
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.matches("lua-resty-http", json.headers["user-agent"], nil, true)
      end)

      it("it works when upstream returns 408", function ()
        local res = proxy_client:get("/https-with-https-config/408", params)
        local body = assert.res_status(408, res)
        assert.equals("408", body)
      end)

      it("X-KONG-Upstream-Latency", function()
        local delay = 3
        local res = proxy_client:get("/http-with-https-config/delay/" .. delay, params)

        assert.res_status(200, res)
        assert.not_nil(res.headers["X-KONG-Upstream-Latency"])
        assert.truthy((tonumber(res.headers["X-KONG-Upstream-Latency"]) - delay*1000) < delay*100)
      end)
    end)
  end)
end

