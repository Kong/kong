-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local kong_vitals = require "kong.vitals"
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key


describe("Hybrid vitals", function()
    local vitals
    setup(function()
        local db = select(2, helpers.get_db_utils())

        kong.configuration = {
            role = "control_plane",
            vitals = true,
            license_path = "spec-ee/fixtures/mock_license.json",
            portal_and_vitals_key = get_portal_and_vitals_key(),
        }

        -- with role=control_plane, the vitals.clustering strategy will be used
        vitals = kong_vitals.new({
            db = db,
            ttl_seconds = 3600,
            ttl_minutes = 24 * 60,
            ttl_days = 30,
        })

        vitals:init()
    end)

    describe("with anonymous reports enabled", function()
        it("select_phone_home succeeds and returns no data", function()
            local res = vitals.strategy:select_phone_home()
            assert.equals(#res, 0)
        end)
    end)
end)
