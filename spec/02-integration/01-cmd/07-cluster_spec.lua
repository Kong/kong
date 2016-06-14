local helpers = require "spec.helpers"

local KILL_ALL = "pkill nginx; pkill serf; pkill dnsmasq"

local function exec(args)
  args = args or ""
  return helpers.execute(helpers.bin_path.." "..args.." --prefix "..helpers.test_conf.prefix.." -c "..helpers.test_conf_path)
end

describe("kong cluster", function()
  setup(function()
    helpers.execute(KILL_ALL)
    assert(helpers.start_kong())
  end)
  teardown(function()
    helpers.execute(KILL_ALL)
    helpers.clean_prefix()
  end)

  it("keygen", function()
    local ok, _, stdout, stderr = exec "cluster keygen"
    assert.True(ok)
    assert.equal("", stderr)
    assert.is_string(stdout)
    assert.equal(25, string.len(stdout)) -- 25 = 24 for the key, 1 for the newline
  end)
  it("members", function()
    local ok, _, stdout, stderr = exec "cluster members"
    assert.True(ok)
    assert.equal("", stderr)
    assert.is_string(stdout)
    assert.True(string.len(stdout) > 10)
  end)
  it("reachability", function()
    local ok, _, stdout, stderr = exec "cluster reachability"
    assert.True(ok)
    assert.equal("", stderr)
    assert.is_string(stdout)
    assert.True(string.len(stdout) > 10)
  end)
  describe("#only force-leave", function()
    it("should fail when no node is specified", function()
      local ok, _, stdout, stderr = exec "cluster force-leave"
      assert.False(ok)
      assert.equal("", stdout)
      assert.matches("Error: you need to specify the node name to leave", stderr, nil, true)
    end)
    it("should work when a node is specified", function()
      local ok, _, stdout, stderr = exec "cluster force-leave some-node"
      assert.True(ok)
      assert.equal("", stderr)
      assert.is_string(stdout)
      assert.matches("Force-leaving some-node", stdout, nil, true)
    end)
  end)
end)
