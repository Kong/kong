local schemas = require "kong.dao.schemas_validation"
local validate_entity = schemas.validate_entity
local schema = require "kong.enterprise_edition.dao.schemas.portal_configs"

describe("portal_utils", function()
  describe("schema", function()

    it("should accept properly formatted emails", function()
      local values = {
        portal_emails_from = "dog@kong.com",
        portal_emails_reply_to = "cat@kong.com",
      }

      local valid, _ = validate_entity(values, schema)
      assert.True(valid)
      assert.True(valid)
    end)

    it("should reject when email field is improperly formatted", function()
      local values = {
        portal_emails_from = "dog",
        portal_emails_reply_to = "cat",
      }

      local _, err = validate_entity(values, schema)
      assert.equal("dog is invalid: missing '@' symbol", err.portal_emails_from)
      assert.equal("cat is invalid: missing '@' symbol", err.portal_emails_reply_to)
    end)

    it("should accept properly formatted token expiration", function()
      local values = {
        portal_token_exp = 1000,
      }

      local valid, _ = validate_entity(values, schema)
      assert.True(valid)
    end)

    it("should reject improperly formatted token expiration", function()
      local values = {
        portal_token_exp = -1000,
      }

      local _, err = validate_entity(values, schema)
      assert.equal("`portal_token_exp` must be more than 0", err.portal_token_exp)
    end)

    it("should accept valid auth types", function()
      local values, valid

      values = {
        portal_auth = "basic-auth",
      }
      valid, _ = validate_entity(values, schema)
      assert.True(valid)

      values = {
        portal_auth = "key-auth",
      }
      valid, _ = validate_entity(values, schema)
      assert.True(valid)

      values = {
        portal_auth = "openid-connect",
      }
       valid, _ = validate_entity(values, schema)
      assert.True(valid)
    end)

    it("should reject improperly formatted auth type", function()
      local values = {
        portal_auth = 'something-invalid',
      }

      local _, err = validate_entity(values, schema)
      assert.equal("invalid auth type", err.portal_auth)
    end)
  end)
end)
