local helpers = require "spec.helpers"
local h = require "spec.migration_helpers.200_to_210"
local utils = require "kong.tools.utils"

local fmt = string.format

describe("#db migration oauth2/004_200_to_210 spec", function()
  local _, db

  after_each(function()
    -- Clean up the database schema after each exercise.
    -- This prevents failed migration tests impacting other tests in the CI
    assert(db:schema_reset())
  end)

  describe("#postgres", function()
    before_each(function()
      _, db = helpers.get_db_utils("postgres", nil, nil, {
        stop_namespace = "kong.plugins.oauth2.migrations",
        stop_migration = "004_200_to_210",
      })
    end)

    it("adds columns", function()
      local cn = db.connector
      h.assert_not_pg_has_column(cn, "oauth2_authorization_codes", "challenge", "text")
      h.assert_not_pg_has_column(cn, "oauth2_authorization_codes", "challenge_method", "text")
      h.assert_not_pg_has_column(cn, "oauth2_credentials", "client_type", "text")
      h.assert_not_pg_has_column(cn, "oauth2_credentials", "hash_secret", "boolean")

      -- kong migrations up
      assert(helpers.run_up_migration(db, "oauth2",
                                      "kong.plugins.oauth2.migrations",
                                      "004_200_to_210"))

      h.assert_pg_has_column(cn, "oauth2_authorization_codes", "challenge", "text")
      h.assert_pg_has_column(cn, "oauth2_authorization_codes", "challenge_method", "text")
      h.assert_pg_has_column(cn, "oauth2_credentials", "client_type", "text")
      h.assert_pg_has_column(cn, "oauth2_credentials", "hash_secret", "boolean")
    end)

    it("adds and sets ws_id", function()
      local cn = db.connector
      h.assert_not_pg_has_fkey(cn, "oauth2_credentials", "ws_id")
      h.assert_not_pg_has_fkey(cn, "oauth2_authorization_codes", "ws_id")
      h.assert_not_pg_has_fkey(cn, "oauth2_tokens", "ws_id")
      -- kong migrations up
      assert(helpers.run_up_migration(db, "oauth2",
                                      "kong.plugins.oauth2.migrations",
                                      "004_200_to_210"))

      h.pg_insert(cn, "oauth2_credentials", { id = utils.uuid(), client_id = "before-cred" })
      h.pg_insert(cn, "oauth2_authorization_codes", { id = utils.uuid(), code = "before-code" })
      h.pg_insert(cn, "oauth2_tokens", { id = utils.uuid(), access_token="before-token", refresh_token="before-token" })

      -- MIGRATING
      h.assert_pg_has_fkey(cn, "oauth2_credentials", "ws_id")
      h.assert_pg_has_fkey(cn, "oauth2_authorization_codes", "ws_id")

      -- check default workspace exists and get its id
      local res = assert(cn:query("SELECT * FROM workspaces"))
      assert.equals(1, #res)
      assert.equals("default", res[1].name)
      assert.truthy(utils.is_valid_uuid(res[1].id))
      local default_ws_id = res[1].id

      -- ensure that the entities created by the old node get the default ws_id
      local bc = assert(cn:query("SELECT * FROM oauth2_credentials"))[1]
      assert.equals(default_ws_id, bc.ws_id)

      local bac = assert(cn:query("SELECT * FROM oauth2_authorization_codes"))[1]
      assert.equals(default_ws_id, bac.ws_id)

      local bt = assert(cn:query("SELECT * FROM oauth2_tokens"))[1]
      assert.equals(default_ws_id, bt.ws_id)

      -- create entities without specifying default ws_id (simulate old node)
      local omc = h.pg_insert(cn, "oauth2_credentials", { id = utils.uuid(), client_id="old-migrating-cred" })
      assert.equals(default_ws_id, omc.ws_id)

      local omac = h.pg_insert(cn, "oauth2_authorization_codes", { id = utils.uuid(), code = "old-migrating-code" })
      assert.equals(default_ws_id, omac.ws_id)

      local omt = h.pg_insert(cn, "oauth2_tokens", { id = utils.uuid(), access_token = "old-migrating-token", refresh_token = "old-migrating-token"  })
      assert.equals(default_ws_id, omt.ws_id)

      -- create specifying default ws_id.(simulate new node)
      local nmc = h.pg_insert(cn, "oauth2_credentials", { id = utils.uuid(), ws_id = default_ws_id, client_id = "new-migrating-cred" })
      assert.equals(default_ws_id, nmc.ws_id)

      local nmac = h.pg_insert(cn, "oauth2_authorization_codes", { id = utils.uuid(), ws_id = default_ws_id, code = "new-migrating-code" })
      assert.equals(default_ws_id, nmac.ws_id)

      local nmt = h.pg_insert(cn, "oauth2_tokens", { id = utils.uuid(), ws_id = default_ws_id, access_token="new-migrating-token", refresh_token="new-migrating-token"  })
      assert.equals(default_ws_id, nmt.ws_id)

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "oauth2",
                                            "kong.plugins.oauth2.migrations",
                                            "004_200_to_210"))

      local amc = h.pg_insert(cn, "oauth2_credentials", { id = utils.uuid(), ws_id = default_ws_id, client_id = "after-cred" })
      assert.equals(default_ws_id, amc.ws_id)

      local aac = h.pg_insert(cn, "oauth2_authorization_codes", { id = utils.uuid(), ws_id = default_ws_id, code = "after-code" })
      assert.equals(default_ws_id, aac.ws_id)

      local at = h.pg_insert(cn, "oauth2_tokens", { id = utils.uuid(), ws_id = default_ws_id, access_token="after-token", refresh_token="after-token"  })
      assert.equals(default_ws_id, at.ws_id)

      -- check that previous entities still have ws_id
      local bc = assert(cn:query(fmt("SELECT * FROM oauth2_credentials WHERE id = '%s'", bc.id)))[1]
      assert.equals(default_ws_id, bc.ws_id)

      local omc = assert(cn:query(fmt("SELECT * FROM oauth2_credentials WHERE id = '%s'", omc.id)))[1]
      assert.equals(default_ws_id, omc.ws_id)

      local nmc = assert(cn:query(fmt("SELECT * FROM oauth2_credentials WHERE id = '%s'", nmc.id)))[1]
      assert.equals(default_ws_id, nmc.ws_id)

      local bac = assert(cn:query(fmt("SELECT * FROM oauth2_authorization_codes WHERE id = '%s'", bac.id)))[1]
      assert.equals(default_ws_id, bac.ws_id)

      local omac = assert(cn:query(fmt("SELECT * FROM oauth2_authorization_codes WHERE id = '%s'", omac.id)))[1]
      assert.equals(default_ws_id, omac.ws_id)

      local nmac = assert(cn:query(fmt("SELECT * FROM oauth2_authorization_codes WHERE id = '%s'", nmac.id)))[1]
      assert.equals(default_ws_id, nmac.ws_id)

      local bt = assert(cn:query(fmt("SELECT * FROM oauth2_tokens WHERE id = '%s'", bt.id)))[1]
      assert.equals(default_ws_id, bt.ws_id)

      local omt = assert(cn:query(fmt("SELECT * FROM oauth2_tokens WHERE id = '%s'", omt.id)))[1]
      assert.equals(default_ws_id, omt.ws_id)

      local nmt = assert(cn:query(fmt("SELECT * FROM oauth2_tokens WHERE id = '%s'", nmt.id)))[1]
      assert.equals(default_ws_id, nmt.ws_id)
    end)
  end)

  describe("#cassandra", function()
    before_each(function()
      _, db = helpers.get_db_utils("cassandra", nil, nil, {
        stop_namespace = "kong.plugins.oauth2.migrations",
        stop_migration = "004_200_to_210",
      })
    end)

    it("adds columns", function()
      local cn = db.connector
      h.assert_not_c_has_column(cn, "oauth2_authorization_codes", "challenge", "text")
      h.assert_not_c_has_column(cn, "oauth2_authorization_codes", "challenge_method", "text")
      h.assert_not_c_has_column(cn, "oauth2_credentials", "client_type", "text")
      h.assert_not_c_has_column(cn, "oauth2_credentials", "hash_secret", "boolean")

      -- kong migrations up
      assert(helpers.run_up_migration(db, "oauth2",
                                      "kong.plugins.oauth2.migrations",
                                      "004_200_to_210"))

      h.assert_c_has_column(cn, "oauth2_authorization_codes", "challenge", "text")
      h.assert_c_has_column(cn, "oauth2_authorization_codes", "challenge_method", "text")
      h.assert_c_has_column(cn, "oauth2_credentials", "client_type", "text")
      h.assert_c_has_column(cn, "oauth2_credentials", "hash_secret", "boolean")
    end)

    it("adds and sets ws_id", function()
      local cn = db.connector
      h.assert_not_c_has_fkey(cn, "basicauth-credentials", "ws_id")
      -- kong migrations up
      assert(helpers.run_up_migration(db, "basicauth-credentials",
                                      "kong.plugins.oauth2.migrations",
                                      "004_200_to_210"))

      h.c_insert(cn, "oauth2_credentials", { id = utils.uuid(), client_id = "before-cred" })
      h.c_insert(cn, "oauth2_authorization_codes", { id = utils.uuid(), code = "before-code" })
      h.c_insert(cn, "oauth2_tokens", { id = utils.uuid(), refresh_token = "before-token", access_token = "before-token"  })

      -- MIGRATING
      h.assert_c_has_fkey(cn, "oauth2_credentials", "ws_id")

      -- check default workspace exists and get its id
      local res = assert(cn:query("SELECT * FROM workspaces"))
      assert.equals(1, #res)
      assert.equals("default", res[1].name)
      assert.truthy(utils.is_valid_uuid(res[1].id))
      local default_ws_id = res[1].id

      -- the entities created by the old node don't get the ws_id (this is handled in DAO)
      local bc = assert(cn:query("SELECT * FROM oauth2_credentials"))[1]
      assert.is_nil(bc.ws_id)

      local bac = assert(cn:query("SELECT * FROM oauth2_authorization_codes"))[1]
      assert.is_nil(bac.ws_id)

      local bt = assert(cn:query("SELECT * FROM oauth2_tokens"))[1]
      assert.is_nil(bt.ws_id)

      -- entities created by the old node don't get the default id in C*
      -- (this is handled in the DAO)
      local omc = h.c_insert(cn, "oauth2_credentials", { id = utils.uuid(), client_id = "old-migrating-cred" })
      assert.is_nil(omc.ws_id)

      local omac = h.c_insert(cn, "oauth2_authorization_codes", { id = utils.uuid(), code = "old-migrating-code" })
      assert.is_nil(omac.ws_id)

      local omt = h.c_insert(cn, "oauth2_tokens", { id = utils.uuid(), refresh_token = "old-migrating-token", access_token = "old-migrating-token"  })
      assert.is_nil(omt.ws_id)

      -- create specifying default ws_id.(simulate new node)
      local nmc = h.c_insert(cn, "oauth2_credentials", { id = utils.uuid(), ws_id = default_ws_id, client_id = "new-migrating-cred" })
      assert.equals(default_ws_id, nmc.ws_id)

      local nmac = h.c_insert(cn, "oauth2_authorization_codes", { id = utils.uuid(), code = "new-migrating-code", ws_id = default_ws_id })
      assert.equals(default_ws_id, nmac.ws_id)

      local nmt = h.c_insert(cn, "oauth2_tokens", { id = utils.uuid(), refresh_token = "new-migrating-token", access_token = "new-migrating-token", ws_id = default_ws_id  })
      assert.equals(default_ws_id, nmt.ws_id)

      -- kong migrations finish
      assert(helpers.run_teardown_migration(db, "oauth2",
                                            "kong.plugins.oauth2.migrations",
                                            "004_200_to_210"))

      -- AFTER
      -- create specifying default ws_id.(simulate new node)
      local ac = h.c_insert(cn, "oauth2_credentials", { id = utils.uuid(), ws_id = default_ws_id, client_id="after-cred" })
      assert.equals(default_ws_id, ac.ws_id)

      local aac = h.c_insert(cn, "oauth2_authorization_codes", { id = utils.uuid(), ws_id = default_ws_id, code="after-code" })
      assert.equals(default_ws_id, aac.ws_id)

      local at = h.c_insert(cn, "oauth2_tokens", { id = utils.uuid(), ws_id = default_ws_id, access_token="after-token", refresh_token="after-token" })
      assert.equals(default_ws_id, at.ws_id)

      -- check all the entities with unique keys have been modified with the ws_id
      bc = assert(cn:query(fmt("SELECT * from oauth2_credentials where id=%s", bc.id)))[1]
      assert.same(default_ws_id, bc.ws_id)
      assert.same(default_ws_id .. ":before-cred", bc.client_id)

      bac = assert(cn:query(fmt("SELECT * from oauth2_authorization_codes where id=%s", bac.id)))[1]
      assert.same(default_ws_id, bac.ws_id)
      assert.same(default_ws_id .. ":before-code", bac.code)

      bt = assert(cn:query(fmt("SELECT * from oauth2_tokens where id=%s", bt.id)))[1]
      assert.same(default_ws_id, bt.ws_id)
      assert.same(default_ws_id .. ":before-token", bt.access_token)
      assert.same(default_ws_id .. ":before-token", bt.refresh_token)

      omc = assert(cn:query(fmt("SELECT * from oauth2_credentials where id=%s", omc.id)))[1]
      assert.same(default_ws_id, omc.ws_id)
      assert.same(default_ws_id .. ":old-migrating-cred", omc.client_id)

      omac = assert(cn:query(fmt("SELECT * from oauth2_authorization_codes where id=%s", omac.id)))[1]
      assert.same(default_ws_id, omac.ws_id)
      assert.same(default_ws_id .. ":old-migrating-code", omac.code)

      omt = assert(cn:query(fmt("SELECT * from oauth2_tokens where id=%s", omt.id)))[1]
      assert.same(default_ws_id, omt.ws_id)
      assert.same(default_ws_id .. ":old-migrating-token", omt.access_token)
      assert.same(default_ws_id .. ":old-migrating-token", omt.refresh_token)

      nmc = assert(cn:query(fmt("SELECT * from oauth2_credentials where id=%s", nmc.id)))[1]
      assert.same(default_ws_id, nmc.ws_id)
      assert.same(default_ws_id .. ":new-migrating-cred", nmc.client_id)

      nmac = assert(cn:query(fmt("SELECT * from oauth2_authorization_codes where id=%s", nmac.id)))[1]
      assert.same(default_ws_id, nmac.ws_id)
      assert.same(default_ws_id .. ":new-migrating-code", nmac.code)

      nmt = assert(cn:query(fmt("SELECT * from oauth2_tokens where id=%s", nmt.id)))[1]
      assert.same(default_ws_id, nmt.ws_id)
      assert.same(default_ws_id .. ":new-migrating-token", nmt.access_token)
      assert.same(default_ws_id .. ":new-migrating-token", nmt.refresh_token)
    end)
  end)
end)
