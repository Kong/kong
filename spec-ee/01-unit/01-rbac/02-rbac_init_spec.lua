-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local rbac = require "kong.rbac"


describe("rbac - init.lua", function()
  local merge_roles = rbac.merge_roles

  describe("merge_roles", function()
    it("merges roles successfully", function()
      -- merge element by id
      assert.same({ {id = 1} }, merge_roles({ {id = 1}}, { {id = 1} }))
      assert.same({ {id = 1}, {id = 2} }, merge_roles({ {id = 1}, {id = 2} }, { {id = 2} }))
      assert.same({ {id = 1}, {id = 2}, {id = 3} }, merge_roles({ {id = 1}, {id = 2} }, { {id = 3} }))
      assert.same({{id = 1}}, merge_roles({}, {{id = 1}}))
      assert.same({{id = 1}, {id = 2}}, merge_roles({}, {{id = 1}, {id = 2}}))
    end)

    it('merges roles - immutable', function()
      local roles1 = { {id = 1}, {id = 2}, {id = 3} }
      merge_roles(roles1, { { id = 4 }})
      assert.same(roles1, roles1)
    end)

    it('merges roles - commutative', function()
      -- merges both ways
      assert.same({{id = 2}, {id = 1}, {id = 3}}, merge_roles({{id = 2}}, {{id = 1}, {id = 3}}))
      assert.same({{id = 2}, {id = 3}, {id = 1}}, merge_roles({{id = 2}, {id = 3}}, {{id = 1}}))

    end)
  end)
end)
