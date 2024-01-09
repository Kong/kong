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

    server {
      listen 16796;
      error_log logs/proxy_auth.log debug;

      content_by_lua_block {
        require("spec.fixtures.forward-proxy-server").connect({
          basic_auth = ngx.encode_base64("test:konghq"),
        })
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
              content_by_lua_block {
                  ngx.say('host=' .. ngx.var.http_host)
              }
          }
      }
    ]], prefix, prefix, prefix)
  },
}


fixtures.dns_mock:A {
  name = "proxy.test",
  address = "127.0.0.1",
}

local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

for _, strategy in strategies() do
  describe("forward-proxy auth #" .. strategy, function()
    local proxy_client
    local params = { headers = { host = "proxy.test" } }

    --local strategy = strategy ~= "off" and strategy or nil
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
        url                = "https://proxy.test:16798/",
        client_certificate = bp.certificates:insert {
          cert = ssl_fixtures.cert_client,
          key  = ssl_fixtures.key_client,
        }
      }

      local non_mtls = bp.services:insert {
        url = "https://proxy.test:16798/",
      }

      -- the happy path
      bp.plugins:insert {
        name   = "forward-proxy",
        config = {
          https_proxy_host = "127.0.0.1",
          https_proxy_port = 16797,
        },
        route = bp.routes:insert {
          hosts   = { "proxy.test" },
          paths   = { "/mtls" },
          service = mtls,
        },
      }

      -- service without mtls cert
      bp.plugins:insert {
        name   = "forward-proxy",
        config = {
          https_proxy_host = "127.0.0.1",
          https_proxy_port = 16797,
        },
        route = bp.routes:insert {
          hosts   = { "proxy.test" },
          paths   = { "/no-mtls" },
          service = non_mtls,
        },
      }

      -- no auth
      bp.plugins:insert {
        name   = "forward-proxy",
        config = {
          https_proxy_host = "127.0.0.1",
          https_proxy_port = 16796,
        },
        route = bp.routes:insert {
          hosts   = { "proxy.test" },
          paths   = { "/no-auth" },
          service = mtls,
        },
      }

      -- incorrect auth
      bp.plugins:insert {
        name   = "forward-proxy",
        config = {
          https_proxy_host = "127.0.0.1",
          https_proxy_port = 16796,
          auth_username    = "test",
          auth_password    = "wrong!",
        },
        route = bp.routes:insert {
          hosts   = { "proxy.test" },
          paths   = { "/wrong-auth" },
          service = mtls,
        },
      }

      -- correct auth
      bp.plugins:insert {
        name   = "forward-proxy",
        config = {
          https_proxy_host = "127.0.0.1",
          https_proxy_port = 16796,
          auth_username    = "test",
          auth_password    = "konghq",
        },
        route = bp.routes:insert {
          hosts   = { "proxy.test" },
          paths   = { "/correct-auth" },
          service = mtls,
        },
      }


      assert(helpers.start_kong({
        database   = strategy,
        plugins = "forward-proxy",
        nginx_conf = "spec/fixtures/custom_nginx.template",

        -- this is unused, but required for the the template to include a stream {} block
        stream_listen = "0.0.0.0:5555",
      }, nil, nil, fixtures))

      proxy_client = assert(helpers.proxy_ssl_client(1000, "proxy.test"))
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong(nil, true)
    end)

    describe("mTLS authentication against upstream with Service object, via forward-proxy", function()
      it("no client certificate supplied", function()
        local res = proxy_client:get("/no-mtls", params)

        local body = assert.res_status(400, res)
        assert.matches("400 No required SSL certificate was sent", body, nil, true)

        helpers.wait_until(log_match("proxy.log", "CONNECT proxy.test:16798"), 5)
      end)

      it("client certificate supplied via service.client_certificate", function()
        local res = proxy_client:get("/mtls", params)

        local body = assert.res_status(200, res)
        assert.equals("host=proxy.test:16798", body)

        helpers.wait_until(log_match("proxy.log", "CONNECT proxy.test:16798"), 5)
      end)
    end)

    describe("proxy-authorization header", function()
      local cases = {
        {
          name = "no auth",
          path = "/no-auth",
          status = 500,
          proxy_log = "client did not send proxy-authorization header",
          error_log = "failed to establish a tunnel through a proxy: 401",
        },
        {
          name = "incorrect auth",
          path = "/wrong-auth",
          status = 500,
          proxy_log = "client sent incorrect proxy-authorization",
          error_log = "failed to establish a tunnel through a proxy: 403",
        },
        {
          name = "correct auth",
          path = "/correct-auth",
          status = 200,
          proxy_log = "accepted basic proxy-authorization",
        },
      }

      for _, case in ipairs(cases) do
        it(case.name, function()
          local client = assert(helpers.proxy_ssl_client(1000, "proxy.test"))
          local res = client:get(case.path, params)

          assert.res_status(case.status, res)
          helpers.wait_until(log_match("proxy_auth.log", case.proxy_log), 5)
          if case.error_log then
            helpers.wait_until(log_match("error.log", case.error_log), 5)
          end
        end)
      end
    end)
  end)
end
