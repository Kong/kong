-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uh = require "spec/upgrade_helpers"

describe("database migration", function()

  uh.all_phases("has created the expected new columns", function()
    assert.table_has_column("plugins", "ordering", "jsonb", "text")
    assert.table_has_column("keyring_keys", "id", "text")
    assert.table_has_column("keyring_keys", "key_encrypted", "text")
    assert.table_has_column("keyring_keys", "recovery_key_id", "text")
    assert.table_has_column("keyring_keys", "key_encrypted", "text")
    assert.table_has_column("keyring_keys", "created_at", "timestamp with time zone", "timestamp")
    assert.table_has_column("keyring_keys", "updated_at", "timestamp with time zone", "timestamp")
  end)

  uh.setup(function()
    local database_type = uh.database_type()
    local db = uh.get_database()
    if database_type == 'postgres' then
      local _, err = db.connector:query([[
        INSERT INTO plugins(id, name, config, enabled)
        VALUES('00000000-0000-0000-0000-000000000000', 'statsd-advanced', '{}', true)
        ON CONFLICT (id) DO NOTHING
      ]])
      assert.falsy(err)
    elseif database_type == "cassandra" then
      local _, err = db.connector:query([[
        INSERT INTO plugins(id, name) VALUES(00000000-0000-0000-0000-000000000000, 'statsd-advanced')
      ]])
      assert.falsy(err)
    end
  end)

  uh.new_after_finish("statsd-advaned has been migrated to statsd", function()
    local db = uh.get_database()
    local res, err = db.connector:query("SELECT count(*) FROM plugins WHERE name = 'statsd-advanced'")
    assert.falsy(err)
    assert.equal(0, res[1].count)
  end)
end)
