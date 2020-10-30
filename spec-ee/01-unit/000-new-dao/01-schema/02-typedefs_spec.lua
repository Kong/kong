-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Schema = require "kong.db.schema"
local typedefs = require("kong.enterprise_edition.db.typedefs")


describe("typedefs", function()

  it("features admin_status typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.admin_status }
      }
    })
    for i=0, 4 do
      assert.truthy(Test:validate({ f = i }))
    end
    assert.falsy(Test:validate({ f = 10 }))
    do
      local ok, err = Test:validate({ f = 10})
      assert.falsy(ok)
      assert.matches("invalid ee_user_status value: 10", err.f)
    end
  end)

  it("features consumer_type typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.consumer_type }
      }
    })
    for i=0, 2 do
      assert.truthy(Test:validate({ f = i }))
    end
    assert.falsy(Test:validate({ f = 10 }))
    do
      local ok, err = Test:validate({ f = 50})
      assert.falsy(ok)
      assert.matches("invalid consumer_type value: 50", err.f)
    end
  end)

  it("features email typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.email }
      }
    })
    assert.truthy(Test:validate({ f = 'foo@konghq.com' }))
    assert.truthy(Test:validate({ f = 'foo+test@konghq.com' }))
    assert.falsy(Test:validate({ f = '..@' }))
    assert.falsy(Test:validate({ f = '..@.com' }))
  end)


end)
