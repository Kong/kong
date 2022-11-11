local acme_schema = require "kong.plugins.acme.schema"
local ssl_fixtures = require "spec.fixtures.ssl"
local v = require("spec.helpers").validate_plugin_config_schema

describe("Plugin: acme (schema)", function()

  local tests = {
    {
      name = "accepts valid config",
      input = {
        account_email = "example@example.com",
        api_uri = "https://api.acme.org",
      },
      error = nil
    },
    ----------------------------------------
    {
      name = "rejects invalid email",
      input = {
        account_email = "notaemail",
        api_uri = "https://api.acme.org",
      },
      error = {
        config = {
            account_email = "invalid value: notaemail"
        }
      }
    },
    ----------------------------------------
    {
        name = "must accept ToS for Let's Encrypt (unaccepted,staging)",
        input = {
          account_email = "example@example.com",
          api_uri = "https://acme-staging-v02.api.letsencrypt.org",
        },
        error = {
            ["@entity"] = {
                'terms of service must be accepted, see https://letsencrypt.org/repository/'
            },
            config = {
                tos_accepted = "value must be true",
            },
        },
      },
    ----------------------------------------
    {
        name = "must accept ToS for Let's Encrypt (unaccepted)",
        input = {
          account_email = "example@example.com",
          api_uri = "https://acme-v02.api.letsencrypt.org",
        },
        error = {
            ["@entity"] = {
                'terms of service must be accepted, see https://letsencrypt.org/repository/'
            },
            config = {
                tos_accepted = "value must be true",
            },
        },
      },
    ----------------------------------------
    {
        name = "must accept ToS for Let's Encrypt (accepted)",
        input = {
          account_email = "example@example.com",
          api_uri = "https://acme-v02.api.letsencrypt.org",
          tos_accepted = true,
        },
      },
    ----------------------------------------
    {
        name = "accepts valid account_key",
        input = {
          account_email = "example@example.com",
          api_uri = "https://api.acme.org",
          account_key = ssl_fixtures.key
        },
    },
  }

  for _, t in ipairs(tests) do
    it(t.name, function()
      local output, err = v(t.input, acme_schema)
      assert.same(t.error, err)
      if t.error then
        assert.is_falsy(output)
      else
        assert.is_truthy(output)
      end
    end)
  end

  -- This needs to be a separate test because validating the error cannot be done by
  -- comparing the expected and actual error. The error message returned by openssl
  -- is not stable because it includes values that may change like line number. To
  -- avoid potential test failures in the future, this test checks the error message
  -- for the prefix that we add.
  it("rejects invalid account_key", function()
    local input = {
      account_email = "example@example.com",
      api_uri = "https://api.acme.org",
      account_key = "fake-account-key"
    }

    local output, err = v(input, acme_schema)

    assert.not_nil(err)
    assert.not_nil(err.config)

    local s = err.config.account_key
    assert.equal("invalid key: pkey.new:load_key", string.sub(s, string.find(s, "invalid key: pkey.new:load_key")))

    if err then
      assert.is_falsy(output)
    else
      assert.is_truthy(output)
    end
  end)
end)
