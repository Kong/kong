-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local arguments = require "kong.plugins.openid-connect.arguments"
local introspect = require "kong.plugins.openid-connect.introspect"


local PLUGIN_NAME = "openid-connect"
local ACCESS_TOKEN = "<access-token>"
local OIC = {}


-- default mocked configuration
local CACHE_INTROSPECTION = false
local INTROSPECTION_ENDPOINT = "/introspection_endpoint"
local INTROSPECTION_ENDPOINT_AUTH_METHOD = "private_key_jwt"
local INTROSPECTION_HINT = "hint_val"
local INTROSPECTION_RESULTS = { active = true }
local TTL = 10
local INTROSPECTION_TOKEN_PARAM_NAME = "mytoken"


-- mock openid
local CACHE = {
  introspection = {
    -- function(oic, access_token, hint, ttl, use_cache, ignore_signature, opts)
    load = function(_, _, _, _, _, _, _)
      -- do nothing
      return INTROSPECTION_RESULTS
    end
  }
}


describe(PLUGIN_NAME .. ": (introspect-token-helper)", function()
  it("allows to introspect a token with a given arguments", function()
    local conf = {
      cache_introspection                = CACHE_INTROSPECTION,
      introspection_endpoint             = INTROSPECTION_ENDPOINT,
      introspection_endpoint_auth_method = INTROSPECTION_ENDPOINT_AUTH_METHOD,
      introspection_hint                 = INTROSPECTION_HINT,
      introspection_headers_names        = { "h1" },
      introspection_headers_values       = { "h1val1" },
      introspection_token_param_name     = INTROSPECTION_TOKEN_PARAM_NAME
    }

    local args = arguments(conf, {})

    -- initialize spies
    spy.on(CACHE.introspection, "load")
    spy.on(args, "get_conf_arg")
    spy.on(args, "get_conf_args")

    local introspect_token   = introspect.new(args, OIC, CACHE, false)
    local introspect_results = introspect_token(ACCESS_TOKEN, TTL)

    assert.same(INTROSPECTION_RESULTS, introspect_results)

    -- introspection
    assert.spy(CACHE.introspection.load).was.called(1)

    -- get_conf_arg
    assert.spy(args.get_conf_arg).was.called(8)
    assert.spy(args.get_conf_arg).was.called_with("introspection_endpoint")
    assert.spy(args.get_conf_arg).was.called_with("introspection_endpoint_auth_method")
    assert.spy(args.get_conf_arg).was.called_with("introspection_hint", "access_token")
    assert.spy(args.get_conf_arg).was.called_with("cache_introspection")
    assert.spy(args.get_conf_arg).was.called_with("introspection_post_args_client")
    assert.spy(args.get_conf_arg).was.called_with("introspection_accept", "application/json")
    assert.spy(args.get_conf_arg).was.called_with("introspection_token_param_name")

    -- get_conf_args
    assert.spy(args.get_conf_args).was.called(2)
    assert.spy(args.get_conf_args).was.called_with("introspection_headers_names", "introspection_headers_values")
    assert.spy(args.get_conf_args).was.called_with("introspection_post_args_names", "introspection_post_args_values")

    local expected = {
      headers = {
        Accept = "application/json",
        h1 = "h1val1",
      },
      introspection_endpoint = INTROSPECTION_ENDPOINT,
      introspection_endpoint_auth_method = INTROSPECTION_ENDPOINT_AUTH_METHOD,
      introspection_format = "string",
      token_param_name = INTROSPECTION_TOKEN_PARAM_NAME,
    }

    assert.spy(CACHE.introspection.load).was.called_with(
      OIC,
      ACCESS_TOKEN,
      INTROSPECTION_HINT,
      TTL,
      false,
      false,
      expected
    )

    -- clear spies
    CACHE.introspection.load:revert()
    args.get_conf_arg:revert()
    args.get_conf_args:revert()
  end)

  it("includes the request headers that are being passed to introspection function", function()
    local conf = {
      cache_introspection                = CACHE_INTROSPECTION,
      introspection_endpoint             = INTROSPECTION_ENDPOINT,
      introspection_endpoint_auth_method = INTROSPECTION_ENDPOINT_AUTH_METHOD,
      introspection_hint                 = INTROSPECTION_HINT,
      introspection_headers_names        = { "h1" },
      introspection_headers_values       = { "h1val1" },
      introspection_headers_client       = { "h2", "h3" },
    }

    local args = arguments(conf, {
      ["h2"] = "v2",
      ["h3"] = "v3",
    })

    -- initialize spies
    spy.on(CACHE.introspection, "load")
    spy.on(args, "get_conf_arg")
    spy.on(args, "get_conf_args")

    local introspect_token   = introspect.new(args, OIC, CACHE, false)
    local introspect_results = introspect_token(ACCESS_TOKEN, TTL)

    assert.same(INTROSPECTION_RESULTS, introspect_results, false)

    local expected_headers = {
      Accept = "application/json",
      ["h1"] = "h1val1",
      ["h2"] = "v2",
      ["h3"] = "v3",
    }

    local expected = {
      headers = expected_headers,
      introspection_endpoint = INTROSPECTION_ENDPOINT,
      introspection_endpoint_auth_method = INTROSPECTION_ENDPOINT_AUTH_METHOD,
      introspection_format = "string",
    }

    assert.spy(CACHE.introspection.load).was.called_with(
      OIC,
      ACCESS_TOKEN,
      INTROSPECTION_HINT,
      TTL,
      false,
      false,
      expected
    )

    -- clear spies
    CACHE.introspection.load:revert()
    args.get_conf_arg:revert()
    args.get_conf_args:revert()
  end)

  it("client headers override the statically configured headers", function()
    local conf = {
      cache_introspection                = CACHE_INTROSPECTION,
      introspection_endpoint             = INTROSPECTION_ENDPOINT,
      introspection_endpoint_auth_method = INTROSPECTION_ENDPOINT_AUTH_METHOD,
      introspection_hint                 = INTROSPECTION_HINT,
      introspection_headers_names        = { "h1" },
      introspection_headers_values       = { "h1val1" },
      introspection_headers_client       = { "h1", "h2", "h3" },
    }

    local args = arguments(conf, {
      Accept = "application/json",
      ["h1"] = "v1",
      ["h2"] = "v2",
      ["h3"] = "v3",
    })


    -- initialize spies
    spy.on(CACHE.introspection, "load")
    spy.on(args, "get_conf_arg")
    spy.on(args, "get_conf_args")

    local introspect_token   = introspect.new(args, OIC, CACHE, false)
    local introspect_results = introspect_token(ACCESS_TOKEN, TTL)

    assert.same(INTROSPECTION_RESULTS, introspect_results, false)

    local expected_headers = {
      Accept = "application/json",
      ["h1"] = "v1",
      ["h2"] = "v2",
      ["h3"] = "v3",
    }

    local expected = {
      headers = expected_headers,
      introspection_endpoint = INTROSPECTION_ENDPOINT,
      introspection_endpoint_auth_method = INTROSPECTION_ENDPOINT_AUTH_METHOD,
      introspection_format = "string",
    }

    assert.spy(CACHE.introspection.load).was.called_with(
      OIC,
      ACCESS_TOKEN,
      INTROSPECTION_HINT,
      TTL,
      false,
      false,
      expected
    )

    -- clear spies
    CACHE.introspection.load:revert()
    args.get_conf_arg:revert()
    args.get_conf_args:revert()
  end)
end)
