local helpers = require "spec.helpers"
local merge = kong.table.merge
local cjson = require "cjson"

for _, strategy in helpers.all_strategies() do
  describe("db.key_sets #" .. strategy, function()
    local bp, db, keyset, jwk, pem_pub, pem_priv

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy ~= "off" and strategy or nil, {
        "keys",
        "key_sets"})

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
      local key_set, err = kong.db.key_sets:select(keyset)
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
      local ok, d_err = kong.db.key_sets:delete(key_set)
      assert.is_nil(d_err)
      assert.is_truthy(ok)
    end)

    it(":update updates a keyset's fields", function()
      local key_set, err = kong.db.key_sets:update(keyset, {
        name = "changed"
      })
      assert.is_nil(err)
      assert(key_set.name == "changed")
    end)

    it(":delete cascades correctly", function ()
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
      local key_select, select_err = kong.db.keys:select(key)
      assert.is_nil(select_err)
      assert.is_not_nil(key_select)
      -- delete the set
      local ok, d_err = kong.db.key_sets:delete(key_set)
      assert.is_true(ok)
      assert.is_nil(d_err)
      -- verify if key is gone
      local key_select_deleted, select_deleted_err = kong.db.keys:select(key)
      assert.is_nil(select_deleted_err)
      assert.is_nil(key_select_deleted)
    end)

    it("allows to have multiple keys with different formats in a set", function ()
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
      for row, err_t in kong.db.keys:each_for_set(key_set) do
        assert.is_nil(err_t)
        rows[i] = row
        i = i + 1
      end
      assert.is_nil(err)
      assert.is_same(2, #rows)
    end)
  end)
end
