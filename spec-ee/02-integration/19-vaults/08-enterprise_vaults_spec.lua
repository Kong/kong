-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local CUSTOM_VAULTS = "./spec-ee/fixtures/custom_vaults"
local CUSTOM_PLUGINS = "./spec/fixtures/custom_plugins"

local LUA_PATH = CUSTOM_VAULTS .. "/?.lua;" ..
                 CUSTOM_VAULTS .. "/?/init.lua;" ..
                 CUSTOM_PLUGINS .. "/?.lua;" ..
                 CUSTOM_PLUGINS .. "/?/init.lua;;"

local fmt = string.format

local secret_dummy_header = "Dummy-Plugin"

local mock_server_port = helpers.get_available_port()

local fixtures = {
  http_mock = {
    test = fmt([[
      server {
          server_name _;
          listen %s;

          location = / {
              content_by_lua_block {
                  ngx.print("helloworld")
              }
          }
      }
    ]], mock_server_port),
  },
}

-- make sure test environment does not have any env license
local function setup_env()
  local kld = os.getenv("KONG_LICENSE_DATA")
  helpers.unsetenv("KONG_LICENSE_DATA")

  local klp = os.getenv("KONG_LICENSE_PATH")
  helpers.unsetenv("KONG_LICENSE_PATH")

  local original_luapath = package.path
  package.path = LUA_PATH .. ';' .. package.path

  return function()
    if kld then
      helpers.setenv("KONG_LICENSE_DATA", kld)
    end

    if klp then
      helpers.setenv("KONG_LICENSE_PATH", klp)
    end

    if original_luapath then
      package.path = original_luapath
    end
  end
end


for _, strategy in helpers.each_strategy() do
  describe("CP/DP sync works with #" .. strategy .. " backend", function()
    local reset_env

    lazy_setup(function()
      reset_env = setup_env()

      local bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "vaults",
        "licenses",
      }, { "dummy" }, { "lic_required_vault" }) -- runs migrations

      assert(bp.vaults:insert({
        name = "lic_required_vault",
        prefix = "test-lic-required-vault",
        config = {
          port = mock_server_port,
        },
      }))

      assert(db.licenses:insert({
        payload = assert(helpers.file.read("spec-ee/fixtures/mock_license.json")),
      }))

      local route = assert(bp.routes:insert({
        name      = "test-host",
        hosts     = { "test1.com" },
        paths     = { "/" },
        service   = assert(bp.services:insert()),
      }))

      -- used by the plugin config test case
      assert(bp.plugins:insert({
        name = "dummy",
        config = {
          resp_header_value = fmt("{vault://%s/%s}",
                                   "test-lic-required-vault", "test-secret"),
        },
        route = { id = route.id },
      }))

      assert(helpers.start_kong({
        role = "control_plane",
        prefix = "servroot1",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_package_path = LUA_PATH,
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
        vaults = "lic_required_vault",
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        log_level = "debug",
        lua_package_path = LUA_PATH,
        vaults = "lic_required_vault",
        dedicated_config_processing = "on",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot1")
      helpers.stop_kong("servroot2")
      reset_env()
    end)

    local proxy_client
    before_each(function()
      proxy_client = helpers.proxy_client(10000, 9002)
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)

    it("enterprise vault should work after CP posting license to DP", function()
      helpers.wait_for_all_config_update({
        disable_ipv6 = true,
        forced_proxy_port = 9002,
      })

      local res = proxy_client:get("/", {
        headers = {
          host = "test1.com",
        }
      })

      assert.res_status(200, res)
      assert.not_nil(res.headers[secret_dummy_header])
      assert.equal("test-secret", res.headers[secret_dummy_header])
    end)
  end)
end
