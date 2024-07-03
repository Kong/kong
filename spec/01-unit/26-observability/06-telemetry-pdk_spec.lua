-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

require "kong.tools.utils"


describe("Telemetry PDK unit tests", function()
  describe("log()", function()
    local old_kong = _G.kong

    lazy_setup(function()
      local kong_global = require "kong.global"
      _G.kong = kong_global.new()
      kong_global.init_pdk(kong)
    end)

    lazy_teardown(function()
      _G.kong = old_kong
    end)

    it("fails as expected with invalid input", function()
      local ok, err = kong.telemetry.log()
      assert.is_nil(ok)
      assert.equals("plugin_name must be a string", err)

      ok, err = kong.telemetry.log("plugin_name")
      assert.is_nil(ok)
      assert.equals("plugin_config must be a table", err)

      ok, err = kong.telemetry.log("plugin_name", {})
      assert.is_nil(ok)
      assert.equals("message_type must be a string", err)
    end)

    it ("considers attributes and message as optional", function()
      local ok, err = kong.telemetry.log("plugin_name", {}, "message_type")
      assert.is_nil(ok)
      assert.matches("Telemetry logging is disabled", err)
    end)
  end)
end)
