local helpers          = require "spec.helpers"
local dao_helpers      = require "spec.02-integration.03-dao.helpers"
local feature_flags    = require "kong.enterprise_edition.feature_flags"

describe("vitals_read_from_tsdb" , function()

  -- in case anything failed, stop kong here
  teardown(helpers.stop_kong)

  it("throws an error if host is not defined", function()
    local ok, err = helpers.start_kong({
      vitals   = true,
      feature_conf_path = "spec/fixtures/ee/vitals_tsdb/feature_vitals_tsdb-missing_host.conf"
    })

    assert.is_false(ok)
    assert.not_nil(err)
    assert.matches("TSDB host or port is not defined", err)

    helpers.stop_kong()

  end)

  it("throws an error if config is not valid JSON", function()
    local ok, err = helpers.start_kong({
      vitals   = true,
      feature_conf_path = "spec/fixtures/ee/vitals_tsdb/feature_vitals_tsdb-invalid_json.conf"
    })

    assert.is_false(ok)
    assert.not_nil(err)
    assert.matches("is not valid JSON for TSDB connection configuration", err)

    helpers.stop_kong()

  end)

  it("throws an error if vitals_tsdb_config is not defined", function()
    local ok, err = helpers.start_kong({
      vitals   = true,
      feature_conf_path = "spec/fixtures/ee/vitals_tsdb/feature_vitals_tsdb-vitals_tsdb_config_not_defined.conf"
    })

    assert.is_false(ok)
    assert.not_nil(err)
    assert.matches(
      string.format("\"%s\" is turned on but \"%s\" is not defined",
        feature_flags.FLAGS.VITALS_READ_FROM_TSDB,
        feature_flags.VALUES.VITALS_TSDB_CONFIG),
    err)

    helpers.stop_kong()

  end)

end)

dao_helpers.for_each_dao(function(kong_conf)
  describe("vitals_read_from_tsdb with " .. kong_conf.database , function()
    -- in case anything failed, stop kong here
    teardown(helpers.stop_kong)

    it("loads TSDB strategy properly", function()
     assert(helpers.start_kong({
        vitals   = true,
        feature_conf_path = "spec/fixtures/ee/vitals_tsdb/feature_vitals_tsdb.conf"
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
end)