local Schema = require "kong.db.schema"
local workspaces = require "kong.db.schema.entities.workspaces"


describe("workspace config", function()
  local schema

  setup(function()
    schema = Schema.new(workspaces)
  end)

  describe("schema", function()
    local snapshot

    before_each(function()
      snapshot = assert:snapshot()
    end)

    after_each(function()
      snapshot:revert()
    end)

    it("should accept properly formatted emails", function()
      local values = {
        name = "test",
        config = {
          portal_emails_from = "dog@kong.com",
          portal_emails_reply_to = "cat@kong.com",
        }
      }

      assert.truthy(schema:validate(values))
    end)

    it("should reject when email field is improperly formatted", function()
      local values = {
        name = "test",
        config = {
          portal_emails_from = "dog",
          portal_emails_reply_to = "cat",
        },
      }

      local ok, err = schema:validate(values)
      assert.falsy(ok)
      assert.equal("dog is invalid: missing '@' symbol", err.config["portal_emails_from"])
      assert.equal("cat is invalid: missing '@' symbol", err.config["portal_emails_reply_to"])
    end)

    it("should accept properly formatted token expiration", function()
      local values = {
        name = "test",
        config = {
          portal_token_exp = 1000,
        },
      }

      assert.truthy(schema:validate(values))
    end)

    it("should reject improperly formatted token expiration", function()
      local values = {
        name = "test",
        config = {
          portal_token_exp = -1000,
        },
      }

      local ok, err = schema:validate(values)
      assert.falsy(ok)
      assert.equal("value must be greater than -1", err.config["portal_token_exp"])
    end)

    it("should accept valid auth types", function()
      local values

      values = {
        name = "test",
        config = {
          portal_auth = "basic-auth",
        },
      }
      assert.truthy(schema:validate(values))

      values = {
        name = "test",
        config = {
          portal_auth = "key-auth",
        }
      }
      assert.truthy(schema:validate(values))

      values = {
        name = "test",
        config = {
          portal_auth = "openid-connect",
        },
      }
      assert.truthy(schema:validate(values))

      -- XXX check with portal team if we really need the empty string
      -- as a possible value
      --values = {
      --  name = "test",
      --  config = {
      --    portal_auth = "",
      --  },
      --}
      --assert.truthy(schema:validate(values))

      values = {
        name = "test",
        config = {
          portal_auth = nil,
        },
      }
      assert.truthy(schema:validate(values))
    end)

    it("should reject improperly formatted auth type", function()
      local values = {
        name = "test",
        config = {
          portal_auth = 'something-invalid',
        },
      }
      assert.falsy(schema:validate(values))
    end)
  end)
end)
