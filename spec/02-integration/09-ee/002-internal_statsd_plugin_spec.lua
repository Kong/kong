local helpers          = require "spec.helpers"
local dao_helpers      = require "spec.02-integration.03-dao.helpers"
local cjson            = require "cjson"

describe("internal_statsd_plugin " , function()

  -- in case anything failed, stop kong here
  teardown(helpers.stop_kong)

  it("throws an error if config is not valid JSON", function()
    local ok, err = helpers.start_kong({
      -- custom_plugins = "statsd-advanced",
      feature_conf_path = "spec/fixtures/ee/internal_statsd/feature_internal_statsd_plugin-invalid_json.conf"
    })

    assert.is_false(ok)
    assert.not_nil(err)
    assert.matches("is not valid JSON for internal statsd-advanced config", err, nil, true)

    helpers.stop_kong()

  end)

  it("throws an error if internal_statsd_plugin_config is not defined", function()
    local ok, err = helpers.start_kong({
      -- custom_plugins = "statsd-advanced",
      feature_conf_path = "spec/fixtures/ee/internal_statsd/feature_internal_statsd_plugin-internal_statsd_plugin_config_not_defined.conf"
    })

    assert.is_false(ok)
    assert.not_nil(err)
    assert.matches("internal statsd is enabled but statsd-advanced configuration is not defined", err, nil, true)

    helpers.stop_kong()

  end)
end)

local test
-- check if the plugin exists or not
local ok, _ = pcall(require, "kong.plugins.statsd-advanced.handler")
if not ok then
  test = pending
else
  test = it
end

dao_helpers.for_each_dao(function(kong_conf)
  describe("internal statsd plugin with " .. kong_conf.database , function()
    -- in case anything failed, stop kong here
    teardown(helpers.stop_kong)

    test("is not loaded when internal_statsd_plugin flag is not set", function()
     assert(helpers.start_kong({
        custom_plugins = "statsd-advanced",
      }))

      local client = helpers.admin_client()

      local res = assert(client:send {
        method = "GET",
        path = "/"
      })
      local body = assert.res_status(200, res)

      local json = cjson.decode(body)

      assert.not_contains("statsd-advanced", json.plugins.enabled_in_cluster)

      helpers.stop_kong()
    end)

    test("is loaded when internal_statsd_plugin flag is set", function()
      assert(helpers.start_kong({
         custom_plugins = "statsd-advanced",
         feature_conf_path = "spec/fixtures/ee/internal_statsd/feature_internal_statsd_plugin.conf"
       }))
 
       local client = helpers.admin_client()
 
       local res = assert(client:send {
         method = "GET",
         path = "/"
       })
       local body = assert.res_status(200, res)
 
       local json = cjson.decode(body)
 
       assert.contains("statsd-advanced", json.plugins.enabled_in_cluster)
 
       helpers.stop_kong()
     end)
  end)
end)
