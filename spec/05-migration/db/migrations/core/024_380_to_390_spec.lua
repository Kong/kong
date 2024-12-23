-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uh = require "spec/upgrade_helpers"

describe("database migration", function()
  uh.old_after_up("has created the \"clustering_sync_version\" table", function()
    assert.database_has_relation("clustering_sync_version")
    assert.table_has_column("clustering_sync_version", "version", "integer")
  end)

  -- XXX EE [[
  uh.old_after_up("has created the \"clustering_sync_delta\" table", function()
    assert.database_has_relation("clustering_sync_delta")
    assert.table_has_column("clustering_sync_delta", "version", "integer")
    assert.table_has_column("clustering_sync_delta", "type", "text")
    assert.table_has_column("clustering_sync_delta", "pk", "json")
    assert.table_has_column("clustering_sync_delta", "ws_id", "uuid")
    assert.table_has_column("clustering_sync_delta", "entity", "json")
  end)
  -- XXX EE ]]
end)
