local uh = require "spec/upgrade_helpers"


describe("database migration", function()
  if uh.database_type() == "postgres" then
    uh.all_phases("does not have ttls table", function()
      assert.not_database_has_relation("ttls")
    end)
  end
end)
