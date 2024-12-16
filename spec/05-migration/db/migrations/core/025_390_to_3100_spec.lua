-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uh = require "spec/upgrade_helpers"

describe("database migration", function()
  uh.old_after_up('has created the "custom_plugins" table', function()
    assert.database_has_relation("custom_plugins")
    assert.table_has_column("custom_plugins", "id", "uuid")
    assert.table_has_column("custom_plugins", "ws_id", "uuid")
    assert.table_has_column("custom_plugins", "name", "text")
    assert.table_has_column("custom_plugins", "schema", "text")
    assert.table_has_column("custom_plugins", "handler", "text")
    assert.table_has_column("custom_plugins", "created_at", "timestamp with time zone")
    assert.table_has_column("custom_plugins", "updated_at", "timestamp with time zone")
    assert.table_has_column("custom_plugins", "tags", "ARRAY")
    assert.table_has_index("custom_plugins", "custom_plugins_tags_idx")
  end)
end)
