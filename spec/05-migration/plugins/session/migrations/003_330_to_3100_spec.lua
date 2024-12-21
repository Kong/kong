local uh = require "spec/upgrade_helpers"

describe("database migration", function()
  if uh.database_type() == "postgres" then
    uh.all_phases("has created the \"session_metadatas\" table", function()
      assert.database_has_relation("session_metadatas")
      assert.table_has_column("session_metadatas", "id", "uuid")
      assert.table_has_column("session_metadatas", "session_id", "uuid")
      assert.table_has_column("session_metadatas", "sid", "text")
      assert.table_has_column("session_metadatas", "subject", "text")
      assert.table_has_column("session_metadatas", "audience", "text")
      assert.table_has_column("session_metadatas", "created_at", "timestamp with time zone", "timestamp")
    end)
  end
end)
