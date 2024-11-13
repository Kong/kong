local uh = require "spec/upgrade_helpers"

describe("database migration", function()
  uh.old_after_up("has created the expected new columns", function()
    assert.table_has_column("clustering_data_planes", "cert_details", "jsonb")
  end)
end)
