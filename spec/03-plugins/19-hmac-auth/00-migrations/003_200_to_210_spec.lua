local helpers = require "spec.helpers"
local h = require "spec.migration_helpers.200_to_210"
local utils = require "kong.tools.utils"

local fmt = string.format

describe("#db migration hmac-auth/003_200_to_210 spec", function()
  local _, db

  after_each(function()
    -- Clean up the database schema after each exercise.
    -- This prevents failed migration tests impacting other tests in the CI
    assert(db:schema_reset())
  end)

  describe("#postgres", function()
    before_each(function()
      _, db = helpers.get_db_utils("postgres", nil, nil, {
        stop_namespace = "kong.plugins.hmac-auth.migrations",
        stop_migration = "003_200_to_210",
      })
    end)

    it("adds and sets ws_id", function()
      local cn = db.connector
      h.assert_not_pg_has_fkey(cn, "hmacauth_credentials", "ws_id")
      -- kong migrations up
      assert(helpers.run_up_migration(db, "hmac-auth",
                                      "kong.plugins.hmac-auth.migrations",
                                      "003_200_to_210"))

      h.pg_insert(cn, "hmacauth_credentials", { id = utils.uuid() })

      -- MIGRATING
      h.assert_pg_has_fkey(cn, "hmacauth_credentials", "ws_id")

      -- check default workspace exists and get its id
      local res = assert(cn:query("SELECT * FROM workspaces"))
      assert.equals(1, #res)
      assert.equals("default", res[1].name)
      assert.truthy(utils.is_valid_uuid(res[1].id))
      local default_ws_id = res[1].id

      -- ensure that the entities created by the old node get the default ws_id
      local bc = assert(cn:query("SELECT * FROM hmacauth_credentials"))[1]
      assert.equals(default_ws_id, bc.ws_id)

      -- create entities without specifying default ws_id (simulate old node)
      local omc = h.pg_insert(cn, "hmacauth_credentials", { id = utils.uuid() })
      assert.equals(default_ws_id, omc.ws_id)

      -- create specifying default ws_id.(simulate new node)
      local nmc = h.pg_insert(cn, "hmacauth_credentials", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, nmc.ws_id)

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "hmac-auth",
                                            "kong.plugins.hmac-auth.migrations",
                                            "003_200_to_210"))

      -- create specifying default ws_id.(simulate new node)
      local ac = h.pg_insert(cn, "hmacauth_credentials", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, ac.ws_id)

      -- check that the previous entities still have ws_id
      local bc = assert(cn:query(fmt("SELECT * FROM hmacauth_credentials WHERE id = '%s'", bc.id)))[1]
      assert.equals(default_ws_id, bc.ws_id)

      local omc = assert(cn:query(fmt("SELECT * FROM hmacauth_credentials WHERE id = '%s'", omc.id)))[1]
      assert.equals(default_ws_id, omc.ws_id)

      local nmc = assert(cn:query(fmt("SELECT * FROM hmacauth_credentials WHERE id = '%s'", nmc.id)))[1]
      assert.equals(default_ws_id, nmc.ws_id)
    end)
  end)

  describe("#cassandra", function()
    before_each(function()
      _, db = helpers.get_db_utils("cassandra", nil, nil, {
        stop_namespace = "kong.plugins.hmac-auth.migrations",
        stop_migration = "003_200_to_210",
      })
    end)

    it("adds and sets ws_id", function()
      local cn = db.connector
      h.assert_not_c_has_fkey(cn, "hmacauth-credentials", "ws_id")
      -- kong migrations up
      assert(helpers.run_up_migration(db, "hmacauth-credentials",
                                      "kong.plugins.hmac-auth.migrations",
                                      "003_200_to_210"))

      h.c_insert(cn, "hmacauth_credentials", { id = utils.uuid() })

      -- MIGRATING
      h.assert_c_has_fkey(cn, "hmacauth_credentials", "ws_id")

      -- check default workspace exists and get its id
      local res = assert(cn:query("SELECT * FROM workspaces"))
      assert.equals(1, #res)
      assert.equals("default", res[1].name)
      assert.truthy(utils.is_valid_uuid(res[1].id))
      local default_ws_id = res[1].id

      -- entities created by the old node don't get the default id in C*
      -- (this is handled in the DAO)
      local a = assert(cn:query("SELECT * FROM hmacauth_credentials"))[1]
      assert.is_nil(a.ws_id)

      -- create entities without specifying default ws_id (simulate old node)
      local a = h.c_insert(cn, "hmacauth_credentials", { id = utils.uuid() })
      assert.is_nil(a.ws_id)

      -- create specifying default ws_id.(simulate new node)
      local a = h.c_insert(cn, "hmacauth_credentials", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, a.ws_id)

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "hmac-auth",
                                            "kong.plugins.hmac-auth.migrations",
                                            "003_200_to_210"))

      -- create specifying default ws_id.(simulate new node)
      local a = h.c_insert(cn, "hmacauth_credentials", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, a.ws_id)
    end)
  end)
end)
