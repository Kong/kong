-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"


local DEBUG_LISTEN_HOST = "0.0.0.0"
local DEBUG_LISTEN_PORT = 9200


-- EXIT CODES
local EC_SUCCESS    = 0
local EC_FAILURE    = 1
local EC_INPROGRESS = 2


for _, strategy in helpers.each_strategy() do
for __, deploy in ipairs({ "traditional", "hybrid" }) do

  -- only used for hybrid mode (data_plane) and traditinal mode
  local function kong_debug_exec(command)
    local env = {
      prefix = helpers.test_conf.prefix,
    }

    local dp_env = {
      role = "data_plane",
      prefix = helpers.test_conf.prefix .. "2" ,
      database = "off",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
    }

    local _, code, stdout, stderr = helpers.kong_exec(
      "debug " .. command, (deploy == "hybrid") and dp_env or env, true)

    return code, stdout, stderr
  end

  describe("kong debug commands #" .. strategy .. " #" .. deploy, function ()
  lazy_setup(function()
    helpers.get_db_utils(strategy)

    if deploy == "traditional" then
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        debug_listen = string.format("%s:%d", DEBUG_LISTEN_HOST, DEBUG_LISTEN_PORT),
        debug_listen_local = true,
      }))

    elseif deploy == "hybrid" then
      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- actively disable it
        debug_listen_local = false,
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        debug_listen = string.format("%s:%d", DEBUG_LISTEN_HOST, DEBUG_LISTEN_PORT),
        -- By default, debug_listen_local is enabled.
        -- debug_listen_local = true,
      }))

    else
      error("unknown deploy mode: " .. deploy)
    end
  end)

  lazy_teardown(function()
    assert(helpers.stop_kong())

    if deploy == "hybrid" then
      assert(helpers.stop_kong("servroot2"))
    end
  end)

  -- test whether the parameter of kong.conf.default works
  local code, stderr, stdout

  if deploy == "hybrid" then

  it("debug_listen_local is disabled for CP", function ()
    -- force debug cli to access the endpoints in CP
    code, stderr, stdout = helpers.kong_exec("debug profiling cpu status", {
      prefix = helpers.test_conf.prefix
    })
    assert.matches("Error: Failed to connect to the debug endpoint:", stderr)
  end)

  it("debug_listen_local is enabled for DP by default", function ()
    code, stdout, stderr = kong_debug_exec("profiling cpu status")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling stopped\n", stdout)
  end)

  end

  -- only test the connectivity, not for the full function of these endpoints

  it("kong debug log_level set|get", function ()
    code, stdout, stderr = kong_debug_exec("log_level get")
    assert.same(EC_SUCCESS, code)
    assert.matches("Current log level: debug\n", stdout)

    code, stdout, stderr = kong_debug_exec("log_level set --level invalid")
    assert.same(EC_FAILURE, code)
    assert.matches("Error: Invalid log_level invalid", stderr)

    code, stdout, stderr = kong_debug_exec("log_level set --level notice")
    if deploy == "hybrid" then
      assert.same(EC_SUCCESS, code)
      assert.matches("Cannot change log level when not using a database\n", stdout)

    else
      assert.same(EC_SUCCESS, code)
      assert.matches("Log level changed to notice\n", stdout)
    end

    code, stdout, stderr = kong_debug_exec("log_level get")
    assert.same(EC_SUCCESS, code)
    assert.matches("Current log level: ", stdout)
  end)

  it("kong debug profiling cpu", function ()
    code, stdout, stderr = kong_debug_exec("profiling cpu status")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling stopped\n", stdout)

    code, stdout, stderr = kong_debug_exec("profiling cpu start --mode time --interval 1000 --timeout 60")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling is activated on pid: ", stdout)

    code, stdout, stderr = kong_debug_exec("profiling cpu start --mode time --interval 1000 --timeout 60")
    assert.same(EC_INPROGRESS, code)
    assert.matches("Profiling is already active on pid: ", stderr)

    code, stdout, stderr = kong_debug_exec("profiling cpu status")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling is active on pid: ", stdout)
    assert.matches("Profiling file: ", stdout)

    code, stdout, stderr = kong_debug_exec("profiling cpu stop")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling stopped on pid: ", stdout)

    code, stdout, stderr = kong_debug_exec("profiling cpu stop")
    assert.same(EC_FAILURE, code)
    assert.matches("Profiling is not active", stderr)

    code, stdout, stderr = kong_debug_exec("profiling cpu start --mode instruction --step 1000")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling is activated on pid: ", stdout)

    code, stdout, stderr = kong_debug_exec("profiling cpu stop")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling stopped on pid: ", stdout)

    code, stdout, stderr = kong_debug_exec("profiling cpu stop")
    assert.same(EC_FAILURE, code)
    assert.matches("Profiling is not active", stderr)
  end)

  it("kong debug profiling memory", function ()
    code, stdout, stderr = kong_debug_exec("profiling memory status")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling stopped\n", stdout)

    code, stdout, stderr = kong_debug_exec("profiling memory start --stack_depth 7 --timeout 9")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling is activated on pid: ", stdout)

    code, stdout, stderr = kong_debug_exec("profiling memory status")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling is active on pid: ", stdout)
    assert.matches("Profiling file: ", stdout)

    code, stdout, stderr = kong_debug_exec("profiling memory stop")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling stopped on pid: ", stdout)

    code, stdout, stderr = kong_debug_exec("profiling memory stop")
    assert.same(EC_FAILURE, code)
    assert.matches("Profiling is not active", stderr)
  end)

  it("kong debug profiling gc-snapshot", function ()
    code, stdout, stderr = kong_debug_exec("profiling gc-snapshot")
    assert.same(EC_SUCCESS, code)
    assert.matches("Waiting for gc%-snapshot profiling to complete", stdout)
    assert.matches("Profiling stopped on pid: ", stdout)

    code, stdout, stderr = kong_debug_exec("profiling gc-snapshot --timeout 10")
    assert.same(EC_SUCCESS, code)
    assert.matches("Profiling stopped on pid: ", stdout)

    -- NOTE: The profiling gc-snapshot endpoint has not implemented `stop` API.
    code, stdout, stderr = kong_debug_exec("profiling gc-snapshot stop")
    assert.same(EC_FAILURE, code)
    assert.matches("Invalid profiling commands", stderr)
  end)
end)

end
end
