-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require("spec.helpers")
local cjson   = require("cjson")

local _ACCEPTABLE_ACS_RESPONSE = {
  categoriesAnalysis = {
    [1] = {
      category = "Hate",
      severity = 0,
    },
    [2] = {
      category = "Violence",
      severity = 0,
    },
  },
}

local _BREACHED_ACS_RESPONSE = {
  categoriesAnalysis = {
    [1] = {
      category = "Hate",
      severity = 2,
    },
    [2] = {
      category = "Violence",
      severity = 4,
    },
  },
}

local _BREACHED_CATEGORIES_ONE = {
  categories = {
    [1] = {
      name = "Hate",
      rejection_level = 4,
    },
    [2] = {
      name = "Violence",
      rejection_level = 2,
    },
  },
}

local _BREACHED_CATEGORIES_MANY = {
  categories = {
    [1] = {
      name = "Hate",
      rejection_level = 1,
    },
    [2] = {
      name = "Violence",
      rejection_level = 2,
    },
  },
}

for _, strategy in helpers.each_strategy() do
  describe("Plugin: ai-azure-content-safety (EE) (unit) [#" .. strategy .. "]", function()

    local handler

    setup(function()
      package.loaded["kong.plugins.ai-azure-content-safety.handler"] = nil
      _G.TEST = true
      handler = require("kong.plugins.ai-azure-content-safety.handler")
    end)

    teardown(function()
      _G.TEST = nil
    end)


    it("permits acceptable content", function()
      local ok, reason, err = handler._check_cog_serv_response(cjson.encode(_ACCEPTABLE_ACS_RESPONSE), _BREACHED_CATEGORIES_MANY)
      assert.is_truthy(reason)
      assert.is_truthy(ok)
      assert.is_falsy(err)
    end)

    it("breaches one category", function()
      local ok, reason, err = handler._check_cog_serv_response(cjson.encode(_BREACHED_ACS_RESPONSE), _BREACHED_CATEGORIES_ONE)
      assert.is_falsy(ok)
      assert.is_falsy(err)
      assert.same("breached category [Violence] at level 2", reason)
    end)

    it("breaches many category", function()
      local ok, reason, err = handler._check_cog_serv_response(cjson.encode(_BREACHED_ACS_RESPONSE), _BREACHED_CATEGORIES_MANY)
      assert.is_falsy(ok)
      assert.is_falsy(err)
      assert.same("breached category [Hate] at level 1; breached category [Violence] at level 2", reason)
    end)

    it("catches decode errors", function()
      local ok, reason, err = handler._check_cog_serv_response("NOT_JSON", _BREACHED_CATEGORIES_MANY)
      assert.is_falsy(ok)
      assert.is_same(reason, "")
      assert.same("content safety introspection failure", err)
    end)

    it("catches wrong azure response", function()
      local ok, reason, err = handler._check_cog_serv_response('{"nothing": false}', _BREACHED_CATEGORIES_MANY)
      assert.is_falsy(ok)
      assert.is_same(reason, "")
      assert.same("content safety introspection is invalid", err)
    end)

  end)
end
