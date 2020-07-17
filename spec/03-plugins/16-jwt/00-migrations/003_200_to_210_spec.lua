local helpers = require "spec.helpers"
local h = require "spec.migration_helpers.200_to_210"
local utils = require "kong.tools.utils"

local fmt = string.format

describe("#db migration jwt/003_200_to_210 spec", function()
  local _, db

  after_each(function()
    -- Clean up the database schema after each exercise.
    -- This prevents failed migration tests impacting other tests in the CI
    assert(db:schema_reset())
  end)

  describe("#postgres", function()
    before_each(function()
      _, db = helpers.get_db_utils("postgres", nil, nil, {
        stop_namespace = "kong.plugins.jwt.migrations",
        stop_migration = "003_200_to_210",
      })
    end)

    it("adds and sets ws_id", function()
      local cn = db.connector
      h.assert_not_pg_has_fkey(cn, "jwt_secrets", "ws_id")
      -- kong migrations up
      assert(helpers.run_up_migration(db, "jwt",
                                      "kong.plugins.jwt.migrations",
                                      "003_200_to_210"))

      h.pg_insert(cn, "jwt_secrets", { id = utils.uuid() })

      -- MIGRATING
      h.assert_pg_has_fkey(cn, "jwt_secrets", "ws_id")

      -- check default workspace exists and get its id
      local res = assert(cn:query("SELECT * FROM workspaces"))
      assert.equals(1, #res)
      assert.equals("default", res[1].name)
      assert.truthy(utils.is_valid_uuid(res[1].id))
      local default_ws_id = res[1].id

      -- ensure that the entities created by the old node get the default ws_id
      local bs = assert(cn:query("SELECT * FROM jwt_secrets"))[1]
      assert.equals(default_ws_id, bs.ws_id)

      -- create entities without specifying default ws_id (simulate old node)
      local oms = h.pg_insert(cn, "jwt_secrets", { id = utils.uuid() })
      assert.equals(default_ws_id, oms.ws_id)

      -- create specifying default ws_id.(simulate new node)
      local nms = h.pg_insert(cn, "jwt_secrets", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, nms.ws_id)

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "jwt",
                                            "kong.plugins.jwt.migrations",
                                            "003_200_to_210"))

      -- create specifying default ws_id.(simulate new node)
      local as = h.pg_insert(cn, "jwt_secrets", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, as.ws_id)


      -- check that entities created previosly still have ws_id
      local bs = assert(cn:query(fmt("SELECT * FROM jwt_secrets WHERE id = '%s'", bs.id)))[1]
      assert.equals(default_ws_id, bs.ws_id)

      local oms = assert(cn:query(fmt("SELECT * FROM jwt_secrets WHERE id = '%s'", oms.id)))[1]
      assert.equals(default_ws_id, oms.ws_id)

      local nms = assert(cn:query(fmt("SELECT * FROM jwt_secrets WHERE id = '%s'", nms.id)))[1]
      assert.equals(default_ws_id, nms.ws_id)
    end)
  end)

  describe("#cassandra", function()
    before_each(function()
      _, db = helpers.get_db_utils("cassandra", nil, nil, {
        stop_namespace = "kong.plugins.jwt.migrations",
        stop_migration = "003_200_to_210",
      })
    end)

    it("adds and sets ws_id", function()
      local cn = db.connector
      h.assert_not_c_has_fkey(cn, "jwt_secrets", "ws_id")
      -- kong migrations up
      assert(helpers.run_up_migration(db, "jwt",
                                      "kong.plugins.jwt.migrations",
                                      "003_200_to_210"))

      h.c_insert(cn, "jwt_secrets", { id = utils.uuid() })

      -- MIGRATING
      h.assert_c_has_fkey(cn, "jwt_secrets", "ws_id")

      -- check default workspace exists and get its id
      local res = assert(cn:query("SELECT * FROM workspaces"))
      assert.equals(1, #res)
      assert.equals("default", res[1].name)
      assert.truthy(utils.is_valid_uuid(res[1].id))
      local default_ws_id = res[1].id

      -- entities created by the old node don't get the default id in C*
      -- (this is handled in the DAO)
      local a = assert(cn:query("SELECT * FROM jwt_secrets"))[1]
      assert.is_nil(a.ws_id)

      -- create entities without specifying default ws_id (simulate old node)
      local a = h.c_insert(cn, "jwt_secrets", { id = utils.uuid() })
      assert.is_nil(a.ws_id)

      -- create specifying default ws_id.(simulate new node)
      local a = h.c_insert(cn, "jwt_secrets", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, a.ws_id)

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "jwt",
                                            "kong.plugins.jwt.migrations",
                                            "003_200_to_210"))

      -- create specifying default ws_id.(simulate new node)
      local a = h.c_insert(cn, "jwt_secrets", { id = utils.uuid(), ws_id = default_ws_id })
      assert.equals(default_ws_id, a.ws_id)
    end)
  end)
end)
