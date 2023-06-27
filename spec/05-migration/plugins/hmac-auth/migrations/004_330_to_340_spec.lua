local uh = require "spec/upgrade_helpers"

describe("database migration", function ()
  uh.all_phases("has added the public_key column", function ()
    assert.table_has_column("hmacauth_credentials", "public_key", "text")
  end)
end)
