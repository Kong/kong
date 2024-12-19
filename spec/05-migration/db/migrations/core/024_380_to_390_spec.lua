local uh = require "spec/upgrade_helpers"

describe("database migration", function()
  uh.old_after_up("has created the \"clustering_sync_version\" table", function()
    assert.database_has_relation("clustering_sync_version")
    assert.table_has_column("clustering_sync_version", "version", "integer")
  end)
end)
