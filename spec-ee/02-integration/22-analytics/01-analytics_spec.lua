-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"

local analytics_mock = [[
  server {
      server_name kong_cluster_telemetry_listener;
> for _, entry in ipairs(cluster_telemetry_listeners) do
      listen $(entry.listener) ssl;
> end

      access_log off;

      ssl_verify_client   optional_no_ca;
      ssl_certificate     ${{CLUSTER_CERT}};
      ssl_certificate_key ${{CLUSTER_CERT_KEY}};
      ssl_session_cache   shared:ClusterSSL:10m;

      location = /v1/analytics/reqlog {
          content_by_lua_block {
              ngx.log(ngx.INFO, "Got analytics connection from ", ngx.var.arg_node_id)
              local pl_path = require "pl.path"
              local conf_loader = require "kong.conf_loader"
              local conf_path = pl_path.join(ngx.config.prefix(), ".kong_env")
              local config = assert(conf_loader(conf_path, nil, { from_kong_env = true }))
              kong.clustering = require("kong.clustering").new(config)
              Kong.serve_cluster_telemetry_listener()
          }
      }
  }
]]

for _, mode in ipairs({"hybrid", "traditional"}) do

  describe("analytics [#" .. mode .. "] #off", function()
    local node_id
    lazy_setup(function()
      node_id = utils.uuid()
      local fixtures = {
        http_mock = {
          analytics = analytics_mock
        }
      }

      local role
      if mode == "traditional" then
        role = "traditional"
      else
        role = "data_plane"
      end

      -- the telemetry endpoint is used to validate analytics websocket connection can be established
      -- kong is not supposed to process analytics payloads, so some errors are expected
      assert(helpers.start_kong({
        database = "off",
        role = role,
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        lua_package_path = "./?.lua;./?/init.lua;./spec/fixtures/?.lua",
        konnect_mode = true,
        log_level = "info",
        vitals = true,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_telemetry_endpoint = "127.0.0.1:9006",
        cluster_telemetry_listen = "127.0.0.1:9006",
        cluster_telemetry_server_name = "kong_clustering",
        node_id = node_id,
        admin_listen = "127.0.0.1:8001"
      }, nil, nil, fixtures))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("analytics ws connection established", function()
      assert.logfile().has.line("Got analytics connection from " .. node_id, true, 10)
    end)

    it("no errors when flushing data", function()
      assert.logfile().has.no.line("bad argument #1 to 'set' (string expected, got table", true, 3)
    end)

  end)

end

for _, strategy in helpers.each_strategy() do
  describe("analytics [#traditional] #" .. strategy, function()
    local node_id
    lazy_setup(function()
      node_id = utils.uuid()
      helpers.get_db_utils(strategy)

      local fixtures = {
        http_mock = {
          analytics = analytics_mock
        }
      }

      assert(helpers.start_kong({
        database = strategy,
        role = "traditional",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        lua_package_path = "./?.lua;./?/init.lua;./spec/fixtures/?.lua",
        konnect_mode = true,
        log_level = "info",
        vitals = true,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_telemetry_endpoint = "127.0.0.1:9006",
        cluster_telemetry_listen = "127.0.0.1:9006",
        cluster_telemetry_server_name = "kong_clustering",
        node_id = node_id,
        admin_listen = "127.0.0.1:8001"
      }, nil, nil, fixtures))

    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("analytics ws connection established", function()
      assert.logfile().has.line("Got analytics connection from " .. node_id, true, 10)
    end)

  end)
end
