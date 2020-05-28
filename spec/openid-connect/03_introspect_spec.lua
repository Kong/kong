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


-- mock openid
local CACHE = {
  introspection = {
    -- function(oic, access_token, hint, ttl, use_cache, opts)
    load = function(_, _, _, _, _, _)
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
    }

    local args = arguments(conf, {})

    -- initialize spies
    spy.on(CACHE.introspection, "load")
    spy.on(args, "get_conf_arg")
    spy.on(args, "get_conf_args")

    local introspect_token   = introspect.new(args, OIC, CACHE)
    local introspect_results = introspect_token(ACCESS_TOKEN, TTL)

    assert.same(INTROSPECTION_RESULTS, introspect_results)

    -- introspection
    assert.spy(CACHE.introspection.load).was.called(1)

    -- get_conf_arg
    assert.spy(args.get_conf_arg).was.called(6)
    assert.spy(args.get_conf_arg).was.called_with("introspection_endpoint")
    assert.spy(args.get_conf_arg).was.called_with("introspection_endpoint_auth_method")
    assert.spy(args.get_conf_arg).was.called_with("introspection_hint", "access_token")
    assert.spy(args.get_conf_arg).was.called_with("cache_introspection")
    assert.spy(args.get_conf_arg).was.called_with("introspection_post_args_client")

    -- get_conf_args
    assert.spy(args.get_conf_args).was.called(2)
    assert.spy(args.get_conf_args).was.called_with("introspection_headers_names", "introspection_headers_values")
    assert.spy(args.get_conf_args).was.called_with("introspection_post_args_names", "introspection_post_args_values")

    local expected = {
      headers = {
        h1 = "h1val1"
      },
      introspection_endpoint = INTROSPECTION_ENDPOINT,
      introspection_endpoint_auth_method = INTROSPECTION_ENDPOINT_AUTH_METHOD,
    }

    assert.spy(CACHE.introspection.load).was.called_with(
      OIC,
      ACCESS_TOKEN,
      INTROSPECTION_HINT,
      TTL,
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

    local introspect_token   = introspect.new(args, OIC, CACHE)
    local introspect_results = introspect_token(ACCESS_TOKEN, TTL)

    assert.same(INTROSPECTION_RESULTS, introspect_results)

    local expected_headers = {
      ["h1"] = "h1val1",
      ["h2"] = "v2",
      ["h3"] = "v3",
    }

    local expected = {
      headers = expected_headers,
      introspection_endpoint = INTROSPECTION_ENDPOINT,
      introspection_endpoint_auth_method = INTROSPECTION_ENDPOINT_AUTH_METHOD,
    }

    assert.spy(CACHE.introspection.load).was.called_with(
      OIC,
      ACCESS_TOKEN,
      INTROSPECTION_HINT,
      TTL,
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
      ["h1"] = "v1",
      ["h2"] = "v2",
      ["h3"] = "v3",
    })


    -- initialize spies
    spy.on(CACHE.introspection, "load")
    spy.on(args, "get_conf_arg")
    spy.on(args, "get_conf_args")

    local introspect_token   = introspect.new(args, OIC, CACHE)
    local introspect_results = introspect_token(ACCESS_TOKEN, TTL)

    assert.same(INTROSPECTION_RESULTS, introspect_results)

    local expected_headers = {
      ["h1"] = "v1",
      ["h2"] = "v2",
      ["h3"] = "v3",
    }

    local expected = {
      headers = expected_headers,
      introspection_endpoint = INTROSPECTION_ENDPOINT,
      introspection_endpoint_auth_method = INTROSPECTION_ENDPOINT_AUTH_METHOD,
    }

    assert.spy(CACHE.introspection.load).was.called_with(
      OIC,
      ACCESS_TOKEN,
      INTROSPECTION_HINT,
      TTL,
      false,
      expected
    )

    -- clear spies
    CACHE.introspection.load:revert()
    args.get_conf_arg:revert()
    args.get_conf_args:revert()
  end)
end)
