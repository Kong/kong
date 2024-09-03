-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local ada = require("resty.ada")


local assert = assert
local describe = describe
local it = it


local equal = assert.equal
local is_nil = assert.is_nil
local is_table = assert.is_table


local function is_err(msg, ok, err)
  is_nil(ok)
  equal(msg, err)
  return ok, err
end


describe("Ada", function()
  describe("URL", function()
    describe(".parse", function()
      it("rejects invalid url", function()
        is_err("invalid url", ada.parse("<invalid>"))
      end)
      it("accepts valid url", function()
        is_table(ada.parse("http://www.google.com/"))
      end)
    end)
  end)
end)
