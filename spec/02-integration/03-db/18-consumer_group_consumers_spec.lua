-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local kong = kong

-- Note: include "off" strategy here as well
for _, strategy in helpers.each_strategy() do
  describe("db.consumer_group_consumers #" .. strategy, function()
    local bp, db, consumer_group, consumer

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "consumers",
        "consumer_groups",
        "consumer_group_consumers",
      })
      _G.kong.db = db

      consumer = assert(bp.consumers:insert {
        username = "GRUCEO@kong.com",
        custom_id = "12345",
        created_at = 1000,
      })

      consumer_group = assert(bp.consumer_groups:insert {
        name = "testGroup"
      })

      assert(bp.consumer_group_consumers:insert {
        consumer       = { id = consumer.id },
        consumer_group = { id = consumer_group.id },
      })
    end)

    lazy_teardown(function()
      db.consumers:truncate()
      db.consumer_groups:truncate()
      db.consumer_group_consumers:truncate()
    end)

    it("consumer_group_consumers:count_consumers_in_group() #" .. strategy, function()
      local count, err = kong.db.consumer_group_consumers:count_consumers_in_group(consumer_group.id)
      assert.is_nil(err)
      assert.equal(1, count)
    end)

  end)
end
