-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local keyauth_enc_credentials = require "kong.plugins.key-auth-enc.keyauth_enc_credentials"

describe("keyauth_enc_credentials key identifiers", function()
  local cred = { key = "key_kong" }
  local sha1_ident, sha256_ident

  lazy_setup(function()
    sha1_ident = keyauth_enc_credentials:key_ident(cred, true)
    sha256_ident = keyauth_enc_credentials:key_ident(cred, false)
  end)

  it("correctly generates identifiers", function()
    local expected_sha1_ident = "d9ab8"
    local expected_sha256_ident = "4661f"
    assert.equal(sha1_ident, expected_sha1_ident)
    assert.equal(sha256_ident, expected_sha256_ident)
  end)

  it("falls back to sha1 based identifier if sha256 ident is not found", function()
    keyauth_enc_credentials.strategy = {
      select_ids_by_ident = function() end
    }
    stub(keyauth_enc_credentials.strategy, "select_ids_by_ident")

    keyauth_enc_credentials:validate_unique({ key = "key_kong" })

    assert.stub(keyauth_enc_credentials.strategy.select_ids_by_ident).was_called_with(
      match.is_table(),
      sha256_ident
    )
    assert.stub(keyauth_enc_credentials.strategy.select_ids_by_ident).was_called_with(
      match.is_table(),
      sha1_ident
    )
  end)
end)
