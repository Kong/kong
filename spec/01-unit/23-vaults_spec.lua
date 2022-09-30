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
  local try

  before_each(function()
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
    try = _G.kong.vault.try

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

  describe("try function", function()
    local called

    before_each(function()
      called = 0
    end)

    it("calls the callback only once when successful", function()
      local ok, err = try(function()
        called = called + 1
        return true
      end)

      assert.is_nil(err)
      assert.True(ok)
      assert.equal(1, called)
    end)

    it("calls the callback only once when no options", function()
      local ok, err = try(function()
        called = called + 1
        return nil, "failed"
      end)

      assert.equal("failed", err)
      assert.is_nil(ok)
      assert.equal(1, called)
    end)

    it("calls the callback only once when no refs", function()
      local ok, err = try(function()
        called = called + 1
        return nil, "failed"
      end, {})

      assert.equal("failed", err)
      assert.is_nil(ok)
      assert.equal(1, called)
    end)

    it("calls the callback only once when refs is empty", function()
      local ok, err = try(function()
        called = called + 1
        return nil, "failed"
      end, {
        ["$refs"] = {}
      })

      assert.equal("failed", err)
      assert.is_nil(ok)
      assert.equal(1, called)
    end)

    it("calls the callback twice when current credentials doesn't work", function()
      finally(function()
        helpers.unsetenv("CREDENTIALS")
      end)

      helpers.setenv("CREDENTIALS", '{"username":"jane","password":"qwerty"}')

      local options = {
        username = "john",
        password = "secret",
        ["$refs"] = {
          username = "{vault://env/credentials/username}",
          password = "{vault://env/credentials/password}",
        },
      }

      local callback = function(options)
        called = called + 1
        if options.username ~= "jane" or options.password ~= "qwerty" then
          return nil, "failed"
        end
        return true
      end

      local ok, err = try(callback, options)

      assert.is_nil(err)
      assert.True(ok)
      assert.equal(2, called)

      assert.equal("jane", options.username)
      assert.equal("qwerty", options.password)
      assert.equal("{vault://env/credentials/username}", options["$refs"].username)
      assert.equal("{vault://env/credentials/password}", options["$refs"].password)

      -- has a cache that can be used for rate-limiting

      called = 0
      options = {
        username = "john",
        password = "secret",
        ["$refs"] = {
          username = "{vault://env/credentials/username}",
          password = "{vault://env/credentials/password}",
        },
      }

      helpers.unsetenv("CREDENTIALS")

      -- re-initialize env vault to clear cached values

      local env = require "kong.vaults.env"
      env.init()

      -- if we slept for 10 secs here, the below would fail as rate-limiting
      -- cache would have been cleared

      local ok, err = try(callback, options)

      assert.is_nil(err)
      assert.True(ok)
      assert.equal(2, called)

      assert.equal("jane", options.username)
      assert.equal("qwerty", options.password)
      assert.equal("{vault://env/credentials/username}", options["$refs"].username)
      assert.equal("{vault://env/credentials/password}", options["$refs"].password)
    end)
  end)
end)
