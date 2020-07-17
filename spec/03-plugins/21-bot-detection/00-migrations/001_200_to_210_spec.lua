local helpers = require "spec.helpers"
local h = require "spec.migration_helpers.200_to_210"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

describe("#db migration bot-detection/001_200_to_210 spec", function()
  local _, db

  after_each(function()
    -- Clean up the database schema after each exercise.
    -- This prevents failed migration tests impacting other tests in the CI
    assert(db:schema_reset())
  end)

  describe("#postgres", function()
    before_each(function()
      _, db = helpers.get_db_utils("postgres", nil, nil, {
        stop_namespace = "kong.plugins.bot-detection.migrations",
        stop_migration = "001_200_to_210",
      })
    end)

    it("renames whitelist/blacklist to allow/deny", function()
      local cn = db.connector
      h.pg_insert(cn, "plugins", { id = utils.uuid(),
                                   name = "bot-detection",
                                   enabled = true,
                                   config = '{"whitelist":["foo"],"blacklist":["bar"]}'
                                 })
      -- kong migrations up
      assert(helpers.run_up_migration(db, "bot-detection",
                                      "kong.plugins.bot-detection.migrations",
                                      "001_200_to_210"))

      -- MIGRATING
      -- no changes to test

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "basic-auth",
                                            "kong.plugins.bot-detection.migrations",
                                            "001_200_to_210"))

      local p = assert(cn:query("SELECT * from plugins"))[1]
      assert.same({ allow = { "foo" }, deny = { "bar" } }, p.config)
    end)
  end)

  describe("#cassandra", function()
    before_each(function()
      _, db = helpers.get_db_utils("cassandra", nil, nil, {
        stop_namespace = "kong.plugins.bot-detection.migrations",
        stop_migration = "001_200_to_210",
      })
    end)

    it("renames whitelist/blacklist to allow/deny", function()
      local cn = db.connector
      h.c_insert(cn, "plugins", { id = utils.uuid(),
                                   name = "bot-detection",
                                   enabled = true,
                                   config = '{"whitelist":["foo"],"blacklist":["bar"]}'
                                 })
      -- kong migrations up
      assert(helpers.run_up_migration(db, "bot-detection",
                                      "kong.plugins.bot-detection.migrations",
                                      "001_200_to_210"))

      -- MIGRATING
      -- no changes to test

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "basic-auth",
                                            "kong.plugins.bot-detection.migrations",
                                            "001_200_to_210"))

      local p = assert(cn:query("SELECT * from plugins"))[1]
      local new_config = cjson.decode(p.config)
      assert.same({ allow = { "foo" }, deny = { "bar" } }, new_config)
    end)
  end)
end)
