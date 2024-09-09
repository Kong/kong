-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local upstream_oauth_schema = require("kong.plugins.upstream-oauth.schema")
local oauth_client          = require("kong.plugins.upstream-oauth.oauth-client")
local cache                 = require("kong.plugins.upstream-oauth.cache")

-- helper function to validate data against a schema
local validate
do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema

  function validate(data)
    return validate_entity(data, upstream_oauth_schema)
  end
end


describe("upstream-oauth: (schema)", function()
  it("accepts a minimal config", function()
    local entity, err = validate({
      oauth = {
        token_endpoint = "https://konghq.com/",
        client_id = "test",
        client_secret = "test"
      }
    })

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("does not require client_id and client_secret for auth_method=none", function()
    local entity, err = validate({
      client = {
        auth_method = oauth_client.constants.AUTH_TYPE_NONE
      },
      oauth = {
        token_endpoint = "https://konghq.com/"
      }
    })

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  for _, method in ipairs {
    oauth_client.constants.AUTH_TYPE_CLIENT_SECRET_POST,
    oauth_client.constants.AUTH_TYPE_CLIENT_SECRET_BASIC,
    oauth_client.constants.AUTH_TYPE_CLIENT_SECRET_JWT,
  } do
    it("requires client_id for auth_method=" .. method, function()
      local _, err = validate({
        client = {
          auth_method = method
        },
        oauth = {
          token_endpoint = "https://konghq.com/",
          client_secret = "test"
        }
      })

      assert.is_same({
        ["@entity"] = {
          [1] = "client_id and client_secret must be provided for authentication"
        }
      }, err)
    end)
    it("requires client_secret for auth_method=" .. method, function()
      local _, err = validate({
        client = {
          auth_method = method
        },
        oauth = {
          token_endpoint = "https://konghq.com/",
          client_id = "test"
        }
      })

      assert.is_same({
        ["@entity"] = {
          [1] = "client_id and client_secret must be provided for authentication"
        }
      }, err)
    end)
  end

  it("allows customised headers and post arguments to the idp token endpoint", function()
    local entity, err = validate({
      oauth = {
        client_id = "test",
        client_secret = "test",
        token_endpoint = "https://konghq.com/",
        token_headers = {
          ["Test"] = "Header",
          ["Custom"] = "Header",
        },
        token_post_args = {
          ["scope"] = "profile",
          ["custom"] = "argument",
        }
      }
    })

    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("validates custom header names", function()
    local _, err = validate({
      oauth = {
        client_id = "test",
        client_secret = "test",
        token_endpoint = "https://konghq.com/",
        token_headers = {
          ["BadHeader$"] = "Invalid",
        }
      }
    })
    assert.is_same({
      ["config"] = {
        ["oauth"] = {
          ["token_headers"] = "bad header name 'BadHeader$', allowed characters are A-Z, a-z, 0-9, '_', and '-'"
        }
      }
    }, err)
  end)

  it("requires redis configuration if cache.strategy=redis - allows to fallback to defaults", function()
    local entity, err = validate({
      oauth = {
        client_id = "test",
        client_secret = "test",
        token_endpoint = "https://konghq.com/"
      },
      cache = {
        strategy = cache.constants.STRATEGY_REDIS
      }
    })
    assert.is_nil(err)
    assert.is_truthy(entity)
  end)

  it("requires redis configuration if cache.strategy=redis - no explicit nulls for host/port", function()
    local _, err = validate({
      oauth = {
        client_id = "test",
        client_secret = "test",
        token_endpoint = "https://konghq.com/"
      },
      cache = {
        strategy = cache.constants.STRATEGY_REDIS,
        redis = {
          host = ngx.null,
          port = ngx.null
        }
      }
    })
    assert.is_same({
      ["@entity"] = {
        [1] = "No redis config provided"
      }
    }, err)
  end)
end)
