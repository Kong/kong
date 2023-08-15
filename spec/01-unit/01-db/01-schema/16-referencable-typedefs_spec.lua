-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- needed for validator
require("spec.helpers")
local Schema = require "kong.db.schema"
local typedefs = require("kong.db.schema.typedefs")
local saml_schema = require "kong.plugins.saml.schema"
local request_transformer_advanced_schema = require "kong.plugins.request-transformer-advanced.schema"

local default_reference = '{vault://env/foo/bar}'
local fields = {
  "certificate",
  "key",
  "host",
  "url",
}

describe("referenceable typedefs", function()
  for _, field in ipairs(fields) do
    it("#" .. field, function()
      local Test = Schema.new({
        fields = {
          { f = typedefs[field] { referenceable = true } }
        }
      })
      assert.truthy(Test:validate({ f = default_reference }))
    end)
  end

  local saml_ref_fields = {
    "idp_certificate",
    "response_encryption_key",
    "request_signing_key",
    "request_signing_certificate",
    "session_secret",
    "session_redis_username",
    "session_redis_password",
  }
  for _, saml_field in ipairs(saml_ref_fields) do
  it("#saml #" .. saml_field, function()
    local Test = Schema.new(saml_schema)
    local base_cfg = {
      protocols = { "http" },
      config = {
        assertion_consumer_path = "/foo/bar",
        idp_sso_url = "http://foo.bar",
        issuer = "foo",
        -- len 32
        session_secret = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      }
    }
    base_cfg.config[saml_field] = default_reference
    assert.truthy(Test:validate(base_cfg))
  end)
  end

  it("#request-transformer-advanced #" , function()
    local Test = Schema.new(request_transformer_advanced_schema)
    local base_cfg = {
      protocols = { "http" },
      config = {
        add = {
          headers = {default_reference}
        },
      }
    }
    assert.truthy(Test:validate(base_cfg))
  end)
end)
