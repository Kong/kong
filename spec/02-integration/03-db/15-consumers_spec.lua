-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

-- Note: include "off" strategy here as well
for _, strategy in helpers.all_strategies() do
  describe("db.consumers #" .. strategy, function()
    local bp, db

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "consumers",
      })
      _G.kong.db = db

      assert(bp.consumers:insert {
        username = "GRUCEO@kong.com",
        custom_id = "12345",
        created_at = 1,
      })
    end)

    lazy_teardown(function()
      db.consumers:truncate()
    end)

    it("consumers:select_by_username_ignore_case() ignores username case", function() 
      local consumers, err = kong.db.consumers:select_by_username_ignore_case("gruceo@kong.com")
      assert.is_nil(err)
      assert(#consumers == 1)
      assert(consumers[1])
      assert.same("GRUCEO@kong.com", consumers[1].username)
      assert.same("12345", consumers[1].custom_id)
    end)

    it("consumers:select_by_username_ignore_case() sorts oldest created_at first", function() 
      assert(bp.consumers:insert {
        username = "gruceO@kong.com",
        custom_id = "23456",
        created_at = 2
      })

      assert(bp.consumers:insert {
        username = "GruceO@kong.com",
        custom_id = "34567",
        created_at = 3
      })

      local consumers, err = kong.db.consumers:select_by_username_ignore_case("Gruceo@kong.com")
      assert.is_nil(err)
      assert(#consumers == 3)
      assert.same("gruceo@kong.com", consumers[1].username)
    end)
  end)
end

