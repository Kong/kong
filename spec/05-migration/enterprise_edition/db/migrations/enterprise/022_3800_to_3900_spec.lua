-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local uh = require "spec/upgrade_helpers"

if uh.database_type() == 'postgres' then
  describe("database migration", function()
    uh.new_after_finish("check if constraints `basicauth_credentials_consumer_id_fkey` was created", function()
      local db = uh.get_database()
      local connector = db.connector

      local sql = [[
                    SELECT
                      tc.constraint_name,
                      kcu.column_name
                    FROM
                      information_schema.table_constraints AS tc,
                      information_schema.key_column_usage AS kcu
                    WHERE
                      tc.constraint_type = 'FOREIGN KEY'
                      and tc.constraint_name ='basicauth_credentials_consumer_id_fkey' 
                      and tc.constraint_name = kcu.constraint_name
                      AND tc.table_name = 'basicauth_credentials'
                  ]]
      local constraints = assert(connector:query(sql))
      assert.equals(1, #constraints)
      assert.is_not_nil(constraints[1])
      assert.equals("consumer_id", constraints[1].column_name)
    end)

    uh.new_after_finish("check if constraints `keyauth_credentials_consumer_id_fkey` was created", function()
      local db = uh.get_database()
      local connector = db.connector

      local sql = [[
                    SELECT
                      tc.constraint_name,
                      kcu.column_name
                    FROM
                      information_schema.table_constraints AS tc,
                      information_schema.key_column_usage AS kcu
                    WHERE
                      tc.constraint_type = 'FOREIGN KEY'
                      and tc.constraint_name ='keyauth_credentials_consumer_id_fkey'
                      and tc.constraint_name = kcu.constraint_name
                      AND tc.table_name = 'keyauth_credentials'
                  ]]
      local constraints = assert(connector:query(sql))
      assert.equals(1, #constraints)
      assert.is_not_nil(constraints[1])
      assert.equals("consumer_id", constraints[1].column_name)
    end)
  end)
end
