-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

for _, strategy in helpers.each_strategy() do
  describe("vitals tsdb strategy with #" .. strategy , function()
    local reset_license_data

    lazy_setup(function()
      reset_license_data = clear_license_env()
      assert(helpers.start_kong({
        portal_and_vitals_key = get_portal_and_vitals_key(),
        vitals = "on",
        license_path = "spec-ee/fixtures/mock_license.json",
        feature_conf_path = "spec-ee/fixtures/feature_vitals_tsdb.conf",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      reset_license_data()
    end)

    it("loads TSDB strategy with feature flags properly", function()
      local client = helpers.admin_client()

      local res = assert(client:send {
        method = "GET",
        path = "/vitals"
      })
      assert.res_status(200, res)
    end)
  end)

  describe("vitals tsdb strategy with " .. strategy , function()
    local reset_license_data

    lazy_setup(function()
      reset_license_data = clear_license_env()
      assert(helpers.start_kong({
        portal_and_vitals_key = get_portal_and_vitals_key(),
        vitals = "on",
        vitals_strategy = "database",
        license_path = "spec-ee/fixtures/mock_license.json",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      reset_license_data()
    end)

    it("loads stock vitals properly", function()
      local client = helpers.admin_client()

      local res = assert(client:send {
        method = "GET",
        path = "/vitals"
      })
      assert.res_status(200, res)
    end)
  end)

  pending("vitals tsdb strategy with " .. strategy , function()
    -- mark as pending because we don't have statsd-advanced plugin bundled
    local reset_license_data

    lazy_setup(function()
      reset_license_data = clear_license_env()
      assert(helpers.start_kong({
        portal_and_vitals_key = get_portal_and_vitals_key(),
        vitals = "on",
        vitals_strategy = "prometheus",
        vitals_tsdb_address = "127.0.0.1:9090",
        vitals_statsd_address = "127.0.0.1:8125",
        license_path = "spec-ee/fixtures/mock_license.json",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      reset_license_data()
    end)

    it("loads prometheus strategy properly", function()
      local client = helpers.admin_client()

      local res = assert(client:send {
        method = "GET",
        path = "/vitals"
      })
      assert.res_status(200, res)
    end)
  end)

  describe("vitals tsdb strategy with " .. strategy , function()
    local reset_license_data

    lazy_setup(function()
      reset_license_data = clear_license_env()
    end)

    lazy_teardown(function()
      reset_license_data()
    end)

    it("errors if strategy is unexpected", function()
      local ok, err = helpers.start_kong({
        portal_and_vitals_key = get_portal_and_vitals_key(),
        vitals = "on",
        vitals_strategy = "sometsdb",
        vitals_tsdb_address = "127.0.0.1:9090",
        vitals_statsd_address = "127.0.0.1:8125",
        license_path = "spec-ee/fixtures/mock_license.json",
      })
      assert.is.falsy(ok)
      assert.matches("Error: vitals_strategy must be one of \"database\", \"prometheus\", or \"influxdb\"", err)

      helpers.stop_kong()
    end)
  end)
end
