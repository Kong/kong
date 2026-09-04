local uh = require "spec/upgrade_helpers"

describe("database migration", function ()
  uh.all_phases("has added the plugin_id column", function ()
    assert.table_has_column("oauth2_authorization_codes", "plugin_id", "uuid")
  end)
end)
