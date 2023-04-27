-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local schema_def = require "kong.plugins.hmac-auth.schema"
local v = require("spec.helpers").validate_plugin_config_schema

describe("Plugin: hmac-auth (schema)", function()
  local function setup_global_env()
    _G.kong = _G.kong or {}
    _G.kong.log = _G.kong.log or {
      debug = function(msg)
        ngx.log(ngx.DEBUG, msg)
      end,
      error = function(msg)
        ngx.log(ngx.ERR, msg)
      end,
      warn = function (msg)
        ngx.log(ngx.WARN, msg)
      end
    }
  end

  local previous_kong

  setup(function()
    previous_kong = _G.kong
    setup_global_env()
  end)

  teardown(function()
    _G.kong = previous_kong
  end)

  it("accepts empty config", function()
    local ok, err = v({}, schema_def)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("accepts correct clock skew", function()
    local ok, err = v({ clock_skew = 10 }, schema_def)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("errors with negative clock skew", function()
    local ok, err = v({ clock_skew = -10 }, schema_def)
    assert.is_falsy(ok)
    assert.equal("value must be greater than 0", err.config.clock_skew)
  end)
  it("errors with wrong algorithm", function()
    local ok, err = v({ algorithms = { "sha1024" } }, schema_def)
    assert.is_falsy(ok)
    assert.equal("expected one of: hmac-sha1, hmac-sha256, hmac-sha384, hmac-sha512",
                 err.config.algorithms[1])
  end)
  it("allows hmac-sha1 in non-FIPS mode but disallows in FIPS mode", function()
    local ok = v({ algorithms = { "hmac-sha1" } }, schema_def)
    assert.is_truthy(ok)

    _G.kong = {
      configuration = {
        fips = true
      },
      log = {
        debug = function(msg)
          ngx.log(ngx.DEBUG, msg)
        end,
        error = function(msg)
          ngx.log(ngx.ERR, msg)
        end,
        warn = function (msg)
          ngx.log(ngx.WARN, msg)
        end
      }
    }

    local ok, err = v({ algorithms = { "hmac-sha1" } }, schema_def)
    assert.is_falsy(ok)
    assert.equal('"hmac-sha1" is disabled in FIPS mode',
                 err["@entity"][1])
    _G.kong = nil
  end)
end)
