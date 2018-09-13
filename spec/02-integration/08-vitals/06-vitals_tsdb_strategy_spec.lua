local helpers          = require "spec.helpers"
local dao_helpers      = require "spec.02-integration.03-dao.helpers"

dao_helpers.for_each_dao(function(kong_conf)
  describe("vitals tsdb strategy with " .. kong_conf.database , function()
    -- in case anything failed, stop kong here
    teardown(helpers.stop_kong)

    it("loads TSDB strategy with feature flags properly", function()
     assert(helpers.start_kong({
        vitals = "on",
        feature_conf_path = "spec/fixtures/ee/feature_vitals_tsdb.conf"
      }))

      local client = helpers.admin_client()

      local res = assert(client:send {
        method = "GET",
        path = "/vitals"
      })
      assert.res_status(200, res)

      helpers.stop_kong()
    end)
  end)

  describe("vitals tsdb strategy with " .. kong_conf.database , function()
    -- in case anything failed, stop kong here
    teardown(helpers.stop_kong)

    it("loads stock vitals properly", function()
      assert(helpers.start_kong({
        vitals = "on",
        vitals_strategy = "database"
      }))

      local client = helpers.admin_client()

      local res = assert(client:send {
        method = "GET",
        path = "/vitals"
      })
      assert.res_status(200, res)

      helpers.stop_kong()
    end)
  end)

  pending("vitals tsdb strategy with " .. kong_conf.database , function()
    -- mark as pending because we don't have statsd-advanced plugin bundled
    -- in case anything failed, stop kong here
    teardown(helpers.stop_kong)

    it("loads prometheus strategy properly", function()
      assert(helpers.start_kong({
        vitals = "on",
        vitals_strategy = "prometheus",
        vitals_tsdb_address = "127.0.0.1:9090",
        vitals_statsd_address = "127.0.0.1:8125",
      }))

      local client = helpers.admin_client()

      local res = assert(client:send {
        method = "GET",
        path = "/vitals"
      })
      assert.res_status(200, res)

      helpers.stop_kong()
    end)
  end)

  describe("vitals tsdb strategy with " .. kong_conf.database , function()
    -- in case anything failed, stop kong here
    teardown(helpers.stop_kong)

    it("errors if strategy is unexpected", function()
      local ok, err = helpers.start_kong({
        vitals = "on",
        vitals_strategy = "sometsdb",
        vitals_tsdb_address = "127.0.0.1:9090",
        vitals_statsd_address = "127.0.0.1:8125",
      })
      assert.is.falsy(ok)
      assert.matches("Error: vitals_strategy must be one of \"database\", \"prometheus\", or \"influxdb\"", err)

      helpers.stop_kong()
    end)
  end)
end)
