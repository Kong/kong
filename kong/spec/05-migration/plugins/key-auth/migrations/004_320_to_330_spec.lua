local uh = require "spec/upgrade_helpers"

describe("database migration", function ()
  if uh.database_type() == "postgres" then
    uh.all_phases("has created the expected triggers", function ()
      assert.database_has_trigger("keyauth_credentials_ttl_trigger")
    end)
  end
end)
