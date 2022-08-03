-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uh = require "spec/upgrade_helpers"

if uh.database_type() == 'postgres' then
  describe("acme database migration", function()
      uh.old_after_up("has created the index", function()
          local db = uh.get_database()
          local res, err = db.connector:query([[
            SELECT *
            FROM pg_stat_all_indexes
            WHERE relname = 'acme_storage' AND indexrelname = 'acme_storage_ttl_idx'
          ]])
          assert.falsy(err)
          assert.equal(1, #res)
      end)
  end)
end
