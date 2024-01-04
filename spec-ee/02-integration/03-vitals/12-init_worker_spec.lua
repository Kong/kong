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

  describe("init_worker phase", function()
      local reset_license_data

      lazy_setup(function()
        reset_license_data = clear_license_env()
        helpers.get_db_utils(strategy)
      end)

      lazy_teardown(function()
        reset_license_data()
      end)

      it("doesn't start vitals timer if portal_and_vitals_key is not present", function()
        -- if portal_and_vitals_key is not present, vitals cannot be ever started
        assert(helpers.start_kong({
          database      = strategy,
          log_level     = "debug",
          vitals        = "on",
          license_path  = "spec-ee/fixtures/mock_license.json",
        }))

        finally(function()
          assert(helpers.stop_kong())
        end)

        -- make sure init_worker finished
        assert.errlog().has.line("(re)configuring dns client", true)

        assert.errlog().has.no.line("starting vitals timer", true, 0)
        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("[alert]", true, 0)
        assert.logfile().has.no.line("[crit]", true, 0)
        assert.logfile().has.no.line("[emerg]", true, 0)
      end)

      it("don't start vitals timer if vitals=off and portal_and_vitals_key is present", function()
        -- if portal_and_vitals_key is present, vitals can be started later on
        assert(helpers.start_kong({
          database              = strategy,
          log_level             = "debug",
          vitals                = "off",
          license_path          = "spec-ee/fixtures/mock_license.json",
          portal_and_vitals_key = get_portal_and_vitals_key(),
        }))

        finally(function()
          assert(helpers.stop_kong())
        end)

        -- make sure init_worker finished
        assert.errlog().eventually.has.line("(re)configuring dns client", true)

        assert.errlog().has.no.line("starting vitals timer", true, 0)
        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("[alert]", true, 0)
        assert.logfile().has.no.line("[crit]", true, 0)
        assert.logfile().has.no.line("[emerg]", true, 0)
      end)

      it("start vitals timer if license is missing and portal_and_vitals_key is present", function()
        -- if portal_and_vitals_key is present, vitals can be started later on
        assert(helpers.start_kong({
          database              = strategy,
          log_level             = "debug",
          vitals                = "on",
          portal_and_vitals_key = get_portal_and_vitals_key(),
        }))

        finally(function()
          assert(helpers.stop_kong())
        end)

        -- make sure init_worker finished
        assert.errlog().eventually.has.line("(re)configuring dns client", true)

        assert.errlog().eventually.has.line("starting vitals timer")
        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("[alert]", true, 0)
        assert.logfile().has.no.line("[crit]", true, 0)
        assert.logfile().has.no.line("[emerg]", true, 0)
      end)

  end)

end --for _, strategy in helpers.each_strategy() do

