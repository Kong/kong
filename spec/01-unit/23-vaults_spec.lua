local helpers = require "spec.helpers" -- initializes 'kong' global for vaults
local conf_loader = require "kong.conf_loader"


local is_ref_test_map = {
  ["{vault://x/x}"] = true,
  ["{vault://x/xx}"] = true,
  ["{vault://xx/xx-x}"] = true,
  ["{vault://xxx/xx-x}"] = true,
  ["{vault://;/xx-x}"] = true,
  ["vault:/xx-x}"] = false,
  ["{vault:/xx-x"] = false,
  ["vault:/xx-x"] = false,
  ["{valut:/xx-x}"] = false,
  ["{vault:/xx-x}"] = false,
}


local get_test_map = {
  ["{vault://env/test_secrets}"] = {
    k = "TEST_SECRETS",
    v = "test_value"
  },
  ["{vault://env/test}"] = {
    k = "TEST",
    v = ""
  },
}


describe("Vault PDK", function()
  local vaults
  local is_reference
  local parse_reference
  local dereference

  lazy_setup(function()
    local conf = assert(conf_loader(nil, {
      vaults = "bundled",
      plugins = "bundled",
    }))

    local kong_global = require "kong.global"
    _G.kong = kong_global.new()
    kong_global.init_pdk(kong, conf)

    is_reference = _G.kong.vault.is_reference
    parse_reference = _G.kong.vault.parse_reference
    dereference = _G.kong.vault.get

    vaults = {}

    for vault in pairs(conf.loaded_vaults) do
      local init = require("kong.vaults." .. vault)
      table.insert(vaults, init)
    end
  end)

  it("test init", function()
    local res, err = parse_reference("{vault://env/test}")
    assert.is_nil(err)
    assert.is_nil(res.config)
    assert.is_equal("env", res.name)
    assert.is_equal("test", res.resource)
    assert.is_nil(res.key)
    assert.is_nil(res.version)
  end)

  it("test init nested/path", function()
    local res, err = parse_reference("{vault://env/test-secret/test-key}")
    assert.is_nil(err)
    assert.is_nil(res.config)
    assert.is_equal("env", res.name)
    assert.is_equal("test-secret", res.resource)
    assert.is_equal("test-key", res.key)
    assert.is_nil(res.version)
  end)

  it("test init opts", function()
    local res, err = parse_reference("{vault://env/test?opt1=val1}")
    assert.is_nil(err)
    assert.is_same({ opt1 = "val1" }, res.config)
    assert.is_equal("env", res.name)
    assert.is_equal(res.resource, "test")
    assert.is_nil(res.key)
    assert.is_nil(res.version)
  end)

  it("test init multiple opts", function()
    local res, err = parse_reference("{vault://env/test?opt1=val1&opt2=val2}")
    assert.is_nil(err)
    assert.is_same({ opt1 = "val1", opt2 = "val2" }, res.config)
    assert.is_equal("env", res.name)
    assert.is_equal("test", res.resource)
    assert.is_nil(res.key)
    assert.is_nil(res.version)
  end)

  it("test init version", function()
    local res, err = parse_reference("{vault://env/test#1}")
    assert.is_nil(err)
    assert.is_nil(res.config)
    assert.is_equal("env", res.name)
    assert.is_equal("test", res.resource)
    assert.is_nil(res.key)
    assert.equal(1, res.version)
  end)

  it("ensure that every vault has a VERSION and a `get` field", function()
    for _, vault in ipairs(vaults) do
      assert.not_nil(vault.get)
      assert.not_nil(vault.VERSION)
    end
  end)

  for ref, exp in pairs(is_ref_test_map) do
    it("test is_reference [" .. ref .. "] -> " .. tostring(exp), function()
      assert.is_equal(exp, is_reference(ref))
    end)
  end

  for ref, cfg in pairs(get_test_map) do
    it("test get [" .. ref .. "] -> " .. tostring(cfg.k), function()
      finally(function()
        helpers.unsetenv(cfg.k)
      end)
      helpers.setenv(cfg.k, cfg.v)
      local ret, err = dereference(ref)
      assert.is_nil(err)
      assert.is_equal(cfg.v, ret)
    end)
  end
end)
