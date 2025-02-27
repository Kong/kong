local uh = require "spec/upgrade_helpers"

describe("database migration", function()
  uh.old_after_up("has created the \"clustering_sync_version\" table", function()
    assert.database_has_relation("clustering_sync_version")
    -- Workaround about migration tests happening after 3900 to 31000 is executed before this test
    assert.is.truthy(
      pcall(function()
        assert.table_has_column("clustering_sync_version", "version", "integer")
      end)
      or pcall(function()
        assert.table_has_column("clustering_sync_version", "version", "bigint")
      end)
    )
  end)
end)
