local helpers = require "spec.helpers" -- initializes 'kong' global for vaults
local conf_loader = require "kong.conf_loader"


describe("Environment Variables Vault", function()
  local vaults
  local get

  before_each(function()
    local conf = assert(conf_loader(nil))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf)

    get = _G.kong.vault.get

    vaults = {}

    for vault in pairs(conf.loaded_vaults) do
      local init = require("kong.vaults." .. vault)
      table.insert(vaults, init)
    end
  end)

  it("get undefined", function()
    helpers.unsetenv("TEST_ENV")
    local res, err = get("{vault://env/test_env}")
    assert.is_equal("unable to load value (test_env) from vault (env): not found [{vault://env/test_env}]", err)
    assert.is_nil(res)
  end)

  it("get empty value", function()
    helpers.setenv("TEST_ENV_EMPTY", "")
    finally(function()
      helpers.unsetenv("TEST_ENV_EMPTY")
    end)
    local res, err = get("{vault://env/test_env_empty}")
    assert.is_nil(err)
    assert.is_equal(res, "")
  end)

  it("get text", function()
    helpers.setenv("TEST_ENV", "test")
    finally(function()
      helpers.unsetenv("TEST_ENV")
    end)
    local res, err = get("{vault://env/test_env}")
    assert.is_nil(err)
    assert.is_equal("test", res)
  end)

  it("get json", function()
    helpers.setenv("TEST_ENV_JSON", '{"username":"user", "password":"pass"}')
    finally(function()
      helpers.unsetenv("TEST_ENV_JSON")
    end)
    local res, err = get("{vault://env/test_env_json/username}")
    assert.is_nil(err)
    assert.is_equal(res, "user")
    local pw_res, pw_err = get("{vault://env/test_env_json/password}")
    assert.is_nil(pw_err)
    assert.is_equal(pw_res, "pass")
  end)
end)

