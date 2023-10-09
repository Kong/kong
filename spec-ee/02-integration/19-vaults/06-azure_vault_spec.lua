-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local azure_schema = require("kong.vaults.azure.schema")
local Entity       = require "kong.db.schema.entity"
local azure = assert(Entity.new(azure_schema))

describe("Vault Azure schema", function()
  it("should accept a valid configuration", function()
    local valid_config = {
      vault_uri = "https://myvault.vault.azure.net",
      credentials_prefix = "MY_PREFIX",
      type = "secrets",
      tenant_id = "my-tenant-id",
      client_id = "my-client-id",
      location = "eastus",
      ttl = 60,
      neg_ttl = 30,
      resurrect_ttl = 120,
    }

    local ok, err = azure:validate({ config = valid_config})
    assert.is_nil(err)
    assert.is_true(ok)
  end)

  it("should reject an invalid configuration", function()
    local invalid_config = {
      vault_uri = "https://myvault.vault.azure.net",
      credentials_prefix = "MY_PREFIX",
      type = "invalid_type",
      tenant_id = "my-tenant-id",
      client_id = "my-client-id",
      location = "eastus",
      ttl = 60,
      neg_ttl = 30,
      resurrect_ttl = 120,
    }
    -- `type` is missing.

    local ok, err = azure:validate({ config = invalid_config })
    assert.is_not_nil(err)
    assert.is_nil(ok)
  end)
end)
