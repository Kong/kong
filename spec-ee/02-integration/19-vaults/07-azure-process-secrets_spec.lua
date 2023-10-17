-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers" -- initializes 'kong' global for vaults
local conf_loader = require "kong.conf_loader"
local cjson = require "cjson"
local fmt = string.format

for _, strategy in helpers.each_strategy() do

  describe("Azure Vault Process Secrets s#" .. strategy, function()
    local get
    local AZURE_VAULT_URI

    lazy_setup(function()
      AZURE_VAULT_URI = assert(os.getenv("AZURE_VAULT_URI"))
    end)

    before_each(function()
      -- prevent being overridden
      if AZURE_VAULT_URI then
        helpers.setenv("AZURE_VAULT_URI", AZURE_VAULT_URI)
      end

      local conf = assert(conf_loader(nil))

      local kong_global = require "kong.global"
      _G.kong = kong_global.new()
      kong_global.init_pdk(kong, conf)

      get = _G.kong.vault.get
    end)

    it("check azure_vault_uri transmission via query args", function()
      helpers.setenv("AZURE_VAULT_URI", "")
      local res, err = get("{vault://azure/testing?vault_uri=https://kong-vault.vault.azure.net}")
      assert.is_nil(err)
      assert.is_not_nil(res)
      assert.is_equal(res, "foo")
    end)

    it("check azure_vault_uri transmission via env var", function()
      local res, err = get("{vault://azure/testing}")
      assert.is_nil(err)
      assert.is_not_nil(res)
      assert.is_equal(res, "foo")
    end)
  end)

end
