local uh = require "spec/upgrade_helpers"

describe("database migration", function()
  uh.old_after_up("has created the \"clustering_sync_version\" table", function()
    assert.database_has_relation("clustering_sync_version")
    assert.table_has_column("clustering_sync_version", "version", "serial")
  end)

  uh.old_after_up("has created the \"clustering_sync_delta\" table", function()
    assert.database_has_relation("clustering_sync_delta")
    assert.table_has_column("clustering_sync_delta", "version", "int")
    assert.table_has_column("clustering_sync_delta", "type", "text")
    assert.table_has_column("clustering_sync_delta", "id", "uuid")
    assert.table_has_column("clustering_sync_delta", "ws_id", "uuid")
    assert.table_has_column("clustering_sync_delta", "row", "json")
  end)
end)
