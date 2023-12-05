-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local uuid = require("kong.tools.utils").uuid


local PLUGIN_NAME = "konnect-application-auth"


-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()
  local scope

  lazy_setup(function()
    scope = uuid()
  end)

  it("rejects empty configuration", function ()
    local _, err = validate({})
    assert.is_not_nil(err)
  end)

  it("rejects empty scope", function ()
    local ok, err = validate({
      auth_type = "openid-connect",
    })

    assert.is_same({
      config = {
        scope = "required field missing"
      }
    }, err)
    assert.is_falsy(ok)
  end)

  it("accepts non uuid scope", function ()
    local ok, err = validate({
      auth_type = "openid-connect",
      scope = "not a uuid but thats ok"
    })

    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("applies defaults", function()
    local ok, err = validate({
      scope = scope
    })
    assert.is_nil(err)
    assert.is_truthy(ok)

    assert.is_same({
      auth_type = "openid-connect",
      scope = scope,
      key_names = { "apikey" },
      v2_strategies = {},
    }, ok.config)
  end)

  it("accepts auth_type = openid-connect", function()
    local ok, err = validate({
      auth_type = "openid-connect",
      scope = scope
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts auth_type = key-auth", function()
    local ok, err = validate({
      auth_type = "key-auth",
      scope = scope
    })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("reject invalid auth_type", function()
    local ok, err = validate({
      auth_type = "not openid-connect or key-auth",
      scope = scope
    })

    assert.is_same({
      config = {
        auth_type = 'expected one of: openid-connect, key-auth, v2-strategies'
      },
    }, err)
    assert.is_falsy(ok)
  end)

  describe("v2 auth strategies", function ()
    it("supports openid-connect configs", function ()
      local ok, err = validate({
        auth_type = "v2-strategies",
        scope = uuid(),
        v2_strategies = {
          openid_connect = {
            {
              strategy_id = uuid(),
              config = {
                issuer = "https://accounts.google.com/.well-known/openid-configuration",
              }
            },
            {
              strategy_id = uuid(),
              config = {
                issuer = "https://foo.okta.com/.well-known/openid-configuration",
              }
            }
          }
        }
      })
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)
    it("invalidates bad openid-connect configs missing strategy_id", function ()
      local ok, err = validate({
        auth_type = "v2-strategies",
        scope = uuid(),
        v2_strategies = {
          openid_connect = {
            {
              config = {
                issuer = "https://accounts.google.com/.well-known/openid-configuration",
              }
            }
          }
        }
      })

      assert.is_falsy(ok)
      assert.is_same({
        config = {
          v2_strategies = {
            openid_connect = {
              {
                strategy_id = "required field missing"
              }
            }
          }
        }
      }, err)
    end)
    it("rejects bad openid-connect configs missing required field", function ()
      local ok, err = validate({
        auth_type = "v2-strategies",
        scope = uuid(),
        v2_strategies = {
          openid_connect = {
            {
              strategy_id = uuid(),
              config = {
              }
            }
          }
        }
      })

      assert.is_falsy(ok)
      assert.is_same({
        config = {
          v2_strategies = {
            openid_connect = {
              {
                config = {
                  issuer = "required field missing"
                }
              }
            }
          }
        }
      }, err)
    end)
    it("supports key-auth configs", function ()
      local ok, err = validate({
        auth_type = "v2-strategies",
        scope = uuid(),
        v2_strategies = {
          key_auth = {
            {
              strategy_id = uuid(),
              config = {
                key_names = { "apikey" },
              }
            },
            {
              strategy_id = uuid(),
              config = {
                key_names = { "x-api-key" },
              }
            }
          }
        }
      })
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)
    it("rejects bad key-auth configs missing strategy_id", function ()
      local ok, err = validate({
        auth_type = "v2-strategies",
        scope = uuid(),
        v2_strategies = {
          key_auth = {
            {
              config = {},
            }
          }
        }
      })

      assert.is_falsy(ok)
      assert.is_same({
        config = {
          v2_strategies = {
            key_auth = {
              {
                strategy_id = "required field missing"
              }
            }
          }
        }
      }, err)
    end)
  end)
end)
