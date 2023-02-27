-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local merge = kong.table.merge
local cjson = require "cjson"


for _, strategy in helpers.all_strategies() do
  describe("db.key_sets #" .. strategy, function()
    local bp, db, keyset, jwk, pem_pub, pem_priv

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy ~= "off" and strategy or nil, {
        "keys",
        "key_sets" })

      local jwk_pub, jwk_priv = helpers.generate_keys("JWK")
      pem_pub, pem_priv = helpers.generate_keys("PEM")

      jwk = merge(cjson.decode(jwk_pub), cjson.decode(jwk_priv))

      keyset = assert(bp.key_sets:insert {
        name = "testset",
      })
    end)

    lazy_teardown(function()
      db:truncate("keys")
      db:truncate("key_sets")
    end)

    it(":select returns an item", function()
      local key_set, err = kong.db.key_sets:select({ id = keyset.id })
      assert.is_nil(err)
      assert(key_set.name == keyset.name)
    end)

    it(":insert creates a keyset with name 'this'", function()
      local key_set, err = kong.db.key_sets:insert {
        name = "this"
      }
      assert.is_nil(err)
      assert(key_set.name == "this")
    end)

    it(":delete works", function()
      local key_set, err = kong.db.key_sets:insert {
        name = "that"
      }
      assert.is_nil(err)
      assert(key_set.name == "that")
      local ok, d_err = kong.db.key_sets:delete {
        id = key_set.id
      }
      assert.is_nil(d_err)
      assert.is_truthy(ok)
    end)

    it(":update updates a keyset's fields", function()
      local key_set, err = kong.db.key_sets:update({ id = keyset.id }, {
        name = "changed"
      })
      assert.is_nil(err)
      assert(key_set.name == "changed")
    end)

    it(":delete cascades correctly", function()
      local key_set, err = kong.db.key_sets:insert {
        name = "deletecascade"
      }
      assert(key_set.name == "deletecascade")
      assert.is_nil(err)
      local key, ins_err = kong.db.keys:insert {
        name = "testkey",
        kid = jwk.kid,
        set = key_set,
        jwk = cjson.encode(jwk)
      }
      assert.is_nil(ins_err)
      -- verify creation
      local key_select, select_err = kong.db.keys:select({ id = key.id })
      assert.is_nil(select_err)
      assert.is_not_nil(key_select)
      -- delete the set
      local ok, d_err = kong.db.key_sets:delete {
        id = key_set.id
      }
      assert.is_true(ok)
      assert.is_nil(d_err)
      -- verify if key is gone
      local key_select_deleted, select_deleted_err = kong.db.keys:select({ id = key.id })
      assert.is_nil(select_deleted_err)
      assert.is_nil(key_select_deleted)
    end)

    it("allows to have multiple keys with different formats in a set", function()
      local key_set, err = kong.db.key_sets:insert {
        name = "multikeys"
      }
      assert(key_set.name == "multikeys")
      assert.is_nil(err)
      local pem_key, ins_err = kong.db.keys:insert {
        name = "pem_k",
        kid = "2",
        set = key_set,
        pem = {
          private_key = pem_priv,
          public_key = pem_pub,
        }
      }
      assert.is_nil(ins_err)
      assert.is_not_nil(pem_key)

      local jwk, jwk_ins_err = kong.db.keys:insert {
        name = "jwk_k",
        kid = jwk.kid,
        jwk = cjson.encode(jwk),
        set = key_set,
      }
      assert.is_nil(jwk_ins_err)
      assert.is_not_nil(jwk)

      local rows = {}
      local i = 1
      for row, err_t in kong.db.keys:each_for_set({ id = key_set.id }) do
        assert.is_nil(err_t)
        rows[i] = row
        i = i + 1
      end
      assert.is_nil(err)
      assert.is_same(2, #rows)
    end)
  end)

  describe("db.key_sets rotate feature #" .. strategy, function()
    local bp, db
    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy ~= "off" and strategy or nil, {
        "keys",
        "key_sets" })
    end)

    after_each(function()
      db:truncate("keys")
      db:truncate("key_sets")
    end)

    it(":insert takes jwks_url parameter and sources keys", function()
      local key_set, err = kong.db.key_sets:insert {
        name = "google",
        jwks_url = "https://www.googleapis.com/oauth2/v3/certs"
      }
      assert.is_nil(err)
      assert(key_set.name == "google")
      local rows = {}
      local i = 1
      for row, err_t in kong.db.keys:each_for_set({ id = key_set.id }) do
        assert.is_nil(err_t)
        rows[i] = row
        i = i + 1
      end
      assert.is_nil(err)
      assert.is_same(3, #rows)
    end)

    it(":rotate triggers a rotate operation", function()
      local key_set, err = kong.db.key_sets:insert {
        name = "microsoft",
        jwks_url = "https://login.microsoftonline.com/common/discovery/v2.0/keys"
      }
      assert.is_nil(err)
      assert(key_set.name == "microsoft")
      local rotate_ok, rotate_err = kong.db.key_sets:rotate(key_set)
      assert.is_true(rotate_ok)
      assert.is_nil(rotate_err)
    end)

    it(":rotate triggers a rotate operation but no change is needed", function()
      local key_set, err = kong.db.key_sets:insert {
        name = "google",
        jwks_url = "https://www.googleapis.com/oauth2/v3/certs"
      }
      assert.is_nil(err)
      assert(key_set.name == "google")
      local pre_rotate = {}
      local i = 1
      for row, err_t in kong.db.keys:each_for_set({ id = key_set.id }) do
        assert.is_nil(err_t)
        pre_rotate[i] = row
        i = i + 1
      end
      assert.is_nil(err)
      assert.is_same(3, #pre_rotate)
      local rotate_ok, rotate_err = kong.db.key_sets:rotate(key_set)
      assert.is_true(rotate_ok)
      assert.is_nil(rotate_err)
      local post_rotate = {}
      local j = 1
      for row, err_t in kong.db.keys:each_for_set({ id = key_set.id }) do
        assert.is_nil(err_t)
        post_rotate[j] = row
        j = j + 1
      end
      -- check that they contain the same data as before the rotation.
      assert.same(post_rotate, pre_rotate)
    end)

    it(":rotate triggers no rotate operation when there is no jwks_url", function()
      local key_set, err = kong.db.key_sets:insert {
        name = "no jwks",
      }
      assert.is_nil(err)
      assert(key_set.name == "no jwks")
      local rotate_ok, rotate_err = kong.db.key_sets:rotate(key_set)
      assert.is_true(rotate_ok)
      assert.same("jwks url is required to rotate keys", rotate_err)
    end)

    it("fails with validation error when URL does not contain JWKS", function()
      local key_set, _, err_t = kong.db.key_sets:insert {
        name = "reject invalid URL",
        jwks_url = "http://foobar.notfound"
      }
      assert.is_nil(key_set)
      assert.same(err_t.message, "schema violation (1: could not retrieve keys from the remote resource)")
    end)

    it(":rotate_all runs on multiple key_sets", function()
      assert(kong.db.key_sets:insert {
        name = "google",
        jwks_url = "https://www.googleapis.com/oauth2/v3/certs"
      })
      assert(kong.db.key_sets:insert {
        name = "microsoft",
        jwks_url = "https://login.microsoftonline.com/common/discovery/v2.0/keys"
      })
      local rotate_ok, rotate_err = kong.db.key_sets:rotate_all()
      assert.is_true(rotate_ok)
      assert.is_nil(rotate_err)
    end)
  end)
end
