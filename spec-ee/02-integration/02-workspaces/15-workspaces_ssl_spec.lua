-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ssl_fixtures = require "spec.fixtures.ssl"
local helpers      = require "spec.helpers"


local function get_cert(server_name)
  local _, _, stdout = assert(helpers.execute(
    string.format("echo 'GET /' | openssl s_client -connect 0.0.0.0:%d -servername %s",
                  helpers.get_proxy_port(true), server_name)
  ))

  return stdout
end

for _, strategy in helpers.each_strategy() do
  describe("SSL [#" .. strategy .. "]", function()

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "certificates",
        "snis",
        "workspaces",
      })

      local ssl_workspace_1 = bp.workspaces:insert({
        name = "ssl-1"
      })
      local ssl_workspace_2 = bp.workspaces:insert({
        name = "ssl-2"
      })

      local ssl_workspace_1_cert = bp.certificates:insert_ws ({
        cert = ssl_fixtures.cert,
        key = ssl_fixtures.key,
      }, ssl_workspace_1)
      local ssl_workspace_2_cert = bp.certificates:insert_ws ({
        cert = ssl_fixtures.cert_alt,
        key = ssl_fixtures.key_alt,
      }, ssl_workspace_2)
      local ssl_default_workspace_cert = bp.certificates:insert {
        cert = ssl_fixtures.cert_alt_alt,
        key = ssl_fixtures.key_alt_alt,
      }

      bp.snis:insert_ws ({
        name = "ssl.workspace.com",
        certificate = ssl_workspace_1_cert,
      }, ssl_workspace_1)
      bp.snis:insert_ws ({
        name = "ssl-alt.workspace.com",
        certificate = ssl_workspace_2_cert,
      }, ssl_workspace_2)
      bp.snis:insert {
        name = "default.workspace.com",
        certificate = ssl_default_workspace_cert,
      }

      local ssl_service_1 = bp.services:insert_ws ({
        name = "ssl-workspace-1",
        protocol = helpers.mock_upstream_ssl_protocol,
        host = helpers.mock_upstream_hostname,
        port = helpers.mock_upstream_ssl_port,
      }, ssl_workspace_1)
      local ssl_service_2 = bp.services:insert_ws ({
        name = "ssl-workspace-2",
        protocol = helpers.mock_upstream_ssl_protocol,
        host = helpers.mock_upstream_hostname,
        port = helpers.mock_upstream_ssl_port,
      }, ssl_workspace_2)
      local ssl_default_service = bp.services:insert {
        name = "ssl-default",
        protocol = helpers.mock_upstream_ssl_protocol,
        host = helpers.mock_upstream_hostname,
        port = helpers.mock_upstream_ssl_port,
      }

      bp.routes:insert_ws ({
        protocols = { "https" },
        hosts = { "ssl.workspace.com" },
        service = ssl_service_1,
      }, ssl_workspace_1)
      bp.routes:insert_ws ({
        protocols = { "https" },
        hosts = { "ssl-alt.workspace.com" },
        service = ssl_service_2,
      }, ssl_workspace_2)
      bp.routes:insert {
        protocols = { "https" },
        hosts = { "default.workspace.com" },
        service = ssl_default_service,
      }

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        trusted_ips = "127.0.0.1",
        nginx_http_proxy_ssl_verify = "on",
        nginx_http_proxy_ssl_trusted_certificate = "../spec/fixtures/kong_spec.crt",
      })
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("SSL certificates on workspaces", function()

      it("sets the configured certificate if SNI match", function()
        local cert = get_cert("ssl.workspace.com")
        assert.certificate(cert).has.cn("ssl-example.com")

        local cert = get_cert("ssl-alt.workspace.com")
        assert.certificate(cert).has.cn("ssl-alt.com")

        local cert = get_cert("default.workspace.com")
        assert.certificate(cert).has.cn("ssl-alt-alt.com")
      end)

      it("sets the internal certificate if SNI does not match", function()
        local cert = get_cert("not-ssl.workspace.com")
        assert.certificate(cert).has.cn("localhost")
      end)

    end)
  end)
end
