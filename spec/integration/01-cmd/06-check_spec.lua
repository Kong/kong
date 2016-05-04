local helpers = require "spec.helpers"

local INVALID_CONF_PATH = "spec/fixtures/invalid.conf"

local function exec(args)
  args = args or ""
  return helpers.execute(helpers.bin_path.." "..args)
end

describe("kong check", function()
  it("validates a conf", function()
    local ok, _, stdout, stderr = exec("check -c "..helpers.test_conf_path)
    assert.True(ok)
    assert.equal("", stderr)
    assert.matches("configuration at .- is valid", stdout)
  end)
  it("reports invalid conf", function()
    local ok, _, stdout, stderr = exec("check -c "..INVALID_CONF_PATH)
    assert.False(ok)
    assert.equal("", stdout)
    assert.matches("[error] cassandra_repl_strategy has", stderr, nil, true)
    assert.matches("[error] ssl_cert required", stderr, nil, true)
  end)
  it("doesn't like invaldi files", function()
    local ok, _, stdout, stderr = exec("check -c inexistent.conf")
    assert.False(ok)
    assert.equal("", stdout)
    assert.matches("[error] no file at: inexistent.conf", stderr, nil, true)
  end)
end)
