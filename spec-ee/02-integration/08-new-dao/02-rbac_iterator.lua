local rbac = require "kong.rbac"
local helpers        = require "spec.helpers"


describe("each():", function()
  local bp, db
  lazy_setup(function()
    bp, db  = helpers.get_db_utils("postgres")
    for i=1, 3 do
      bp.services:insert()
    end
  end)

  it("calls rbac validate function", function()
    spy.on(rbac, "validate_entity_operation")
    for row, err in db.services:each() do end
    assert.spy(rbac.validate_entity_operation).was_called(3)
  end)

  it("does not call rbac validate function when skip_rbac = true =", function()
    spy.on(rbac, "validate_entity_operation")
    for row, err in db.services:each(nil, {skip_rbac = true}) do end
    assert.spy(rbac.validate_entity_operation).was_called(0)
  end)

  it("obeys rbac.validate_entity_operation", function()
    local old_val = rbac.validate_entity_operation

    local test_cases = {{ true, 3 }, { false, 0 }}

    for _, tc in ipairs(test_cases) do
      rbac.validate_entity_operation = function() return tc[1] end
      local count = 0
      for row, err in db.services:each() do
        count = count + 1
      end

      assert.equal(count, tc[2])
    end

    rbac.validate_entity_operation = old_val
  end)

end)
