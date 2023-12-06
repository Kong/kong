-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local assert = require "luassert"
local say = require "say"

local PLUGIN_NAME = "app-dynamics"
local MOCK_TRACE_FILENAME = "/tmp/appd-plugin-mock-trace.txt"


local function matches_regex(state, arguments)
  local string = arguments[1]
  local regex = arguments[2]
  if ngx.re.find(string, regex) then
    return true
  else
    return false
  end
end


say:set_namespace("en")
say:set("assertion.matches_regex.positive", [[
Expected
%s
to match regex
%s]])
say:set("assertion.matches_regex.negative", [[
Expected
%s
to not match regex
%s]])
assert:register("assertion", "matches_regex", matches_regex, "assertion.matches_regex.positive", "assertion.matches_regex.negative")


local function slurp(filename)
  local f = assert(io.open(filename, "r"))
  local content = f:read("*all")
  f:close()
  return content
end


local function read_mock_log()
  local result
  helpers.wait_until(function()
      local success, trace = pcall(slurp, MOCK_TRACE_FILENAME)
      if success and ngx.re.match(trace, "appd_bt_end") then
        result = trace
        return true
      end
  end, 5)
  return result
end


for _, strategy in helpers.all_strategies() do
  describe(PLUGIN_NAME .. ": [#" .. strategy .. "]", function()

    -- Create the declarative configuration from the database,
    -- once.  This depends on Kong to have been configured with a
    -- database before.  Note that once we've started Kong with
    -- the `#off` strategy, we can no longer invoke
    -- `helpers.make_yaml_file()` because it requires Kong to be
    -- configured with a database.

    local declarative_config
    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- Inject a test route. No need to create a service, there is a default
      -- service which will echo the request.
      local route1 = bp.routes:insert {
        hosts = { "test1.test" },
      }
      -- add the plugin to test to the route we created
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {},
      }

      declarative_config = strategy == "off" and helpers.make_yaml_file() or nil
    end)

    local client
    local appd_app_name = "KongMock"
    local appd_tier_name = "KongMockTestTier"
    local appd_node_name = "appd-mock-node.example.com"
    local appd_logging_level = 3
    local appd_controller_host = "appd-mock-controller-host.example.com"
    local appd_controller_port = 567
    local appd_controller_use_ssl = 0
    local appd_controller_account = "appd-controller-account"
    local appd_controller_access_key = "appd-controller-access-key"
    local appd_init_timeout_ms = 2345

    local function start_kong(extra_parameters)

      extra_parameters = extra_parameters or {}
      local parameters = {
        -- set the strategy
        database = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = PLUGIN_NAME,
        -- write & load declarative config, only if 'strategy=off'
        declarative_config = declarative_config,
        -- Set package path to make Kong load the mocked AppDynamics SDK FFI module
        lua_package_path = '/kong-plugin/spec/fixtures/?.lua',
        appd_mock_trace_filename = MOCK_TRACE_FILENAME,
        -- AppDynamics SDK parameters

        -- The "App Name" parameter is passed as a vault
        -- reference to verify that vault references are
        -- correctly respolved by the plugin.
        appd_mock_app_name = appd_app_name,
        appd_app_name = "{vault://env/kong-appd-mock-app-name}",
        appd_tier_name = appd_tier_name,
        appd_node_name = appd_node_name,
        appd_logging_level = appd_logging_level,
        appd_controller_host = appd_controller_host,
        appd_controller_port = appd_controller_port,
        appd_controller_use_ssl = appd_controller_use_ssl,
        appd_controller_account = appd_controller_account,
        appd_controller_access_key = appd_controller_access_key,
        appd_init_timeout_ms = appd_init_timeout_ms,
      }

      for k, v in pairs(extra_parameters) do
        parameters[k] = v
      end

      -- start kong
      assert(helpers.start_kong(parameters))
    end

    after_each(function()
      if client then
        client:close()
      end
      os.remove(MOCK_TRACE_FILENAME)
      helpers.stop_kong(nil, true)
    end)

    describe("Plugin and SDK initialization", function()
      it("is correctly performed", function()
        start_kong()
        client = helpers.proxy_client()
        local response = client:get("/request", {
          headers = {
            host = "test1.test",
          }
        })
        assert.response(response).has.status(200)
        local trace = read_mock_log()
        assert.matches_regex(trace, [[appd_config_set_app_name\(<table: 0x.*>, \"]] .. appd_app_name .. [[\"\)]])
        assert.matches_regex(trace, [[appd_config_set_tier_name\(<table: 0x.*>, \"]] .. appd_tier_name .. [[\"\)]])
        assert.matches_regex(trace, [[appd_config_set_node_name\(<table: 0x.*>, \"]] .. appd_node_name .. [[\.0\"\)]])
        assert.matches_regex(trace, [[appd_config_set_logging_min_level\(<table: 0x.*>, ]] .. appd_logging_level .. [[\)]])
        assert.matches_regex(trace, [[appd_config_set_controller_host\(<table: 0x.*>, \"]] .. appd_controller_host .. [[\"\)]])
        assert.matches_regex(trace, [[appd_config_set_controller_port\(<table: 0x.*>, ]] .. appd_controller_port .. [[\)]])
        assert.matches_regex(trace, [[appd_config_set_controller_use_ssl\(<table: 0x.*>, ]] .. appd_controller_use_ssl .. [[\)]])
        assert.matches_regex(trace, [[appd_config_set_controller_account\(<table: 0x.*>, \"]] .. appd_controller_account .. [[\"\)]])
        assert.matches_regex(trace, [[appd_config_set_controller_access_key\(<table: 0x.*>, \"]] .. appd_controller_access_key .. [[\"\)]])
        assert.matches_regex(trace, [[appd_config_set_init_timeout_ms\(<table: 0x.*>, ]] .. appd_init_timeout_ms .. [[\)]])
        assert.no.matches_regex(trace, [[appd_config_set_controller_http_proxy]])

        assert.matches_regex(
          trace,
          [[(?msx)
            ^
            (appd_config_set_[^\n]+\n)+
            appd_sdk_init\(<table:.0x.*>\)\n
            appd_backend_declare\("HTTP",.".*"\)\n
            appd_backend_set_identifying_property\(".*",."HOST",.".*"\)\n
            appd_backend_add\(".*"\)\n
            ]])
      end)
    end)

    describe("Controller host proxy", function()
      it("can be configured", function()
        local appd_controller_http_proxy_host = "mock-proxy-host.example.com"
        local appd_controller_http_proxy_port = 3128
        local appd_controller_http_proxy_username = "mock-me-in"
        local appd_controller_http_proxy_password = "seee-creeet"
        start_kong({
          appd_controller_http_proxy_host = appd_controller_http_proxy_host,
          appd_controller_http_proxy_port = appd_controller_http_proxy_port,
          appd_controller_http_proxy_username = appd_controller_http_proxy_username,
          appd_controller_http_proxy_password = appd_controller_http_proxy_password,
        })
        client = helpers.proxy_client()
        local response = client:get("/request", {
          headers = {
            host = "test1.test",
          }
        })
        assert.response(response).has.status(200)
        local trace = read_mock_log()
        assert.matches_regex(trace, [[appd_config_set_controller_http_proxy_host\(<table: 0x.*>, \"]] .. appd_controller_http_proxy_host .. [[\"\)]])
        assert.matches_regex(trace, [[appd_config_set_controller_http_proxy_port\(<table: 0x.*>, ]] .. appd_controller_http_proxy_port .. [[\)]])
        assert.matches_regex(trace, [[appd_config_set_controller_http_proxy_username\(<table: 0x.*>, \"]] .. appd_controller_http_proxy_username .. [[\"\)]])
        assert.matches_regex(trace, [[appd_config_set_controller_http_proxy_password\(<table: 0x.*>, \"]] .. appd_controller_http_proxy_password .. [[\"\)]])
      end)
    end)

    describe("request", function()
      it("gets a 'singularityheader' header if not set", function()
        start_kong()
        client = helpers.proxy_client()
        local response = client:get("/request", {
          headers = {
            host = "test1.test",
          }
        })
        assert.response(response).has.status(200)
        local header_value = assert.request(response).has.header("singularityheader")
        assert.is_not_nil(header_value)
        local trace = read_mock_log()
        assert.matches_regex(
          trace,
          [[(?msx)
            appd_bt_begin.*
            appd_bt_end.*
            ]])
        -- Make sure that we're not snappshotting successful requests
        assert.no.matches_regex(trace, [[appd_bt_enable_snapshot]])
        assert.no.matches_regex(trace, [[appd_bt_add_error]])
      end)

      it("enables snapshots and reports error to AppDynamics if upstream request fails", function()
        start_kong()
        client = helpers.proxy_client()
        local r = client:get("/status/500", { headers = { host = "test1.test" } })
        assert.response(r).has.status(500)
        -- Make sure that we're enabling snapshots for failing
        -- request and that the upstream status is added to
        -- the errors sent to AppDynamics
        local trace = read_mock_log()
        assert.matches_regex(trace, 'appd_bt_enable_snapshot')
        assert.matches_regex(trace, 'appd_bt_add_error.*.".*500.*"')
      end)
    end)

  end)
end
