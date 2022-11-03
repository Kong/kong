-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.all_strategies() do
  describe("db.jwk_sets #" .. strategy, function()
    local bp, js

    lazy_setup(function()
      bp, _ = helpers.get_db_utils(strategy ~= "off" and strategy or nil, {
        "jwks",
        "jwk_sets"})

      js = assert(bp.jwk_sets:insert {
        name = "test",
      })
    end)

    lazy_teardown(function()
    end)

    it("jwk_sets:select returns an item", function()
      local jwk_set, err = kong.db.jwk_sets:select({ id = js.id })
      assert.is_nil(err)
      assert(jwk_set.name == js.name)
    end)

    it("jwk_sets:insert creates a keyset with name 'this'", function()
      local jwk_set, err = kong.db.jwk_sets:insert {
        name = "this"
      }
      assert.is_nil(err)
      assert(jwk_set.name == "this")
    end)

    it("jwk_sets:delete a keyset will actually delete it", function()
      local jwk_set, err = kong.db.jwk_sets:insert {
        name = "that"
      }
      assert.is_nil(err)
      assert(jwk_set.name == "that")
      local ok, d_err = kong.db.jwk_sets:delete {
        id = jwk_set.id
      }
      assert.is_nil(d_err)
      assert.is_truthy(ok)
    end)

    it("jwk_sets:update updates a keyset's fields", function()
      local jwk_set, err = kong.db.jwk_sets:update({ id = js.id }, {
        name = "changed"
      })
      assert.is_nil(err)
      assert(jwk_set.name == "changed")
    end)
  end)
end
