local uh = require "spec/upgrade_helpers"

describe("database migration", function()
    uh.old_after_up("has created the expected new columns", function()
      assert.table_has_column("ca_certificates", "updated_at", "timestamp")
      assert.table_has_column("certificates", "updated_at", "timestamp")
      assert.table_has_column("consumers", "updated_at", "timestamp")
      assert.table_has_column("plugins", "updated_at", "timestamp")
      assert.table_has_column("snis", "updated_at", "timestamp")
      assert.table_has_column("targets", "updated_at", "timestamp")
      assert.table_has_column("upstreams", "updated_at", "timestamp")
    end)
end)
