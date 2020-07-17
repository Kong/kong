local helpers = require "spec.helpers"
local h = require "spec.migration_helpers.200_to_210"
local utils = require "kong.tools.utils"

local fmt = string.format

describe("#db migration acl/003_200_to_210 spec", function()
  local _, db

  after_each(function()
    -- Clean up the database schema after each exercise.
    -- This prevents failed migration tests impacting other tests in the CI
    assert(db:schema_reset())
  end)

  describe("#postgres", function()
    before_each(function()
      _, db = helpers.get_db_utils("postgres", nil, nil, {
        stop_namespace = "kong.plugins.acl.migrations",
        stop_migration = "003_200_to_210",
      })
    end)

    it("adds and sets ws_id", function()
      local cn = db.connector
      h.assert_not_pg_has_fkey(cn, "acls", "ws_id")
      -- kong migrations up
      assert(helpers.run_up_migration(db, "acl",
                                      "kong.plugins.acl.migrations",
                                      "003_200_to_210"))

      h.pg_insert(cn, "acls", { id = utils.uuid() })

      -- MIGRATING
      h.assert_pg_has_fkey(cn, "acls", "ws_id")

      -- check default workspace exists and get its id
      local res = assert(cn:query("SELECT * FROM workspaces"))
      assert.equals(1, #res)
      assert.equals("default", res[1].name)
      assert.truthy(utils.is_valid_uuid(res[1].id))
      local default_ws_id = res[1].id

      -- ensure that the entities created by the old node get the default ws_id
      local ba = assert(cn:query("SELECT * FROM acls"))[1]
      assert.equals(default_ws_id, ba.ws_id)

      -- create entities without specifying default ws_id (simulate old node)
      local oma = h.pg_insert(cn, "acls", { id = utils.uuid() })
      assert.equals(default_ws_id, oma.ws_id)

      -- create specifying default ws_id.(simulate new node)
      local nma = h.pg_insert(cn, "acls", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, nma.ws_id)

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "acl",
                                            "kong.plugins.acl.migrations",
                                            "003_200_to_210"))

      -- create specifying default ws_id.(simulate new node)
      local a = h.pg_insert(cn, "acls", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, a.ws_id)

      -- check that the old entities still have ws_id
      local ba = assert(cn:query(fmt("SELECT * FROM acls WHERE id = '%s'", ba.id)))[1]
      assert.equals(default_ws_id, ba.ws_id)

      local oma = assert(cn:query(fmt("SELECT * FROM acls WHERE id = '%s'", oma.id)))[1]
      assert.equals(default_ws_id, oma.ws_id)

      local nma = assert(cn:query(fmt("SELECT * FROM acls WHERE id = '%s'", nma.id)))[1]
      assert.equals(default_ws_id, nma.ws_id)
    end)
  end)

  describe("#cassandra", function()
    before_each(function()
      _, db = helpers.get_db_utils("cassandra", nil, nil, {
        stop_namespace = "kong.plugins.acl.migrations",
        stop_migration = "003_200_to_210",
      })
    end)

    it("adds and sets ws_id", function()
      local cn = db.connector
      h.assert_not_c_has_fkey(cn, "acls", "ws_id")
      -- kong migrations up
      assert(helpers.run_up_migration(db, "acl",
                                      "kong.plugins.acl.migrations",
                                      "003_200_to_210"))

      h.c_insert(cn, "acls", { id = utils.uuid() })

      -- MIGRATING
      h.assert_c_has_fkey(cn, "acls", "ws_id")

      -- check default workspace exists and get its id
      local res = assert(cn:query("SELECT * FROM workspaces"))
      assert.equals(1, #res)
      assert.equals("default", res[1].name)
      assert.truthy(utils.is_valid_uuid(res[1].id))
      local default_ws_id = res[1].id

      -- entities created by the old node don't get the default id in C*
      -- (this is handled in the DAO)
      local a = assert(cn:query("SELECT * FROM acls"))[1]
      assert.is_nil(a.ws_id)

      -- create entities without specifying default ws_id (simulate old node)
      local a = h.c_insert(cn, "acls", { id = utils.uuid() })
      assert.is_nil(a.ws_id)

      -- create specifying default ws_id.(simulate new node)
      local a = h.c_insert(cn, "acls", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, a.ws_id)

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "acl",
                                            "kong.plugins.acl.migrations",
                                            "003_200_to_210"))

      -- create specifying default ws_id.(simulate new node)
      local a = h.c_insert(cn, "acls", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, a.ws_id)
    end)
  end)
end)
