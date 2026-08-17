local uh = require "spec/upgrade_helpers"

describe("database migration", function()
    uh.old_after_up("has created the expected new columns", function()
        assert.table_has_column("upstreams", "use_srv_name", "boolean")
    end)
end)
