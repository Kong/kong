-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local PLUGIN_NAME = "app-dynamics"


describe(PLUGIN_NAME .. " plugin", function()
    it("can be added to consumer", function()
        local bp = helpers.get_db_utils(nil, { "plugins", }, { PLUGIN_NAME })

        local consumer = bp.consumers:insert {
          username = "johnboy"
        }

        bp.plugins:insert {
          consumer = consumer,
          name     = PLUGIN_NAME,
          config   = {},
        }
    end)
end)
