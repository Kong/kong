local helpers = require "spec.helpers"
local pl_file = require "pl.file"

describe("kong cluster", function()
  setup(function()
    helpers.prepare_prefix()
  end)
  teardown(function()
    helpers.clean_prefix()
  end)

  it("cluster help", function()
    local _, stderr = helpers.kong_exec "cluster --help"
    assert.not_equal("", stderr)
  end)
  it("generates a key", function()
    local _, stderr, stdout = assert(helpers.kong_exec "cluster keygen")
    assert.equal("", stderr)
    assert.equal(26, #stdout) -- 24 + \r\n
  end)
  it("generates a key from config file", function()
    local _, stderr, stdout = assert(helpers.kong_exec("cluster keygen --conf "..helpers.test_conf_path))
    assert.equal("", stderr)
    assert.equal(26, #stdout) -- 24 + \r\n
  end)

  describe("commands that require a running Serf", function()
    setup(function()
      assert(helpers.kong_exec("start --conf "..helpers.test_conf_path))
    end)
    teardown(function()
      helpers.kill_all()
    end)

    it("shows members", function()
      local _, _, stdout = assert(helpers.kong_exec("cluster members --prefix "..helpers.test_conf.prefix))
      assert.matches("alive", stdout)
    end)
    it("shows reachability", function()
      local _, _, stdout = assert(helpers.kong_exec("cluster reachability --prefix "..helpers.test_conf.prefix))
      assert.matches("Successfully contacted all live nodes", stdout)
    end)
    it("force-leaves a node", function()
      local _, _, stdout = assert(helpers.kong_exec("cluster force-leave 127.0.0.1 --prefix "..helpers.test_conf.prefix))
      assert.matches("left node 127.0.0.1", stdout, nil, true)
    end)
  end)
  
  describe("keys", function()
    setup(function()
      -- Creating a sample keyring file
      local KEYRING_PATH = os.tmpname()
      assert(pl_file.write(KEYRING_PATH, [[
      [
        "QHOYjmYlxSCBhdfiolhtDQ==",
        "daZ2wnuw+Ql+2hCm7vQB6A==",
        "keTZydopxtiTY7HVoqeWGw=="
      ]
      ]]))

      assert(helpers.start_kong({
        cluster_keyring_file = KEYRING_PATH
      }))
    end)

    teardown(function()
      helpers.kill_all()
    end)
    
    it("lists keys", function()
      local ok = helpers.kong_exec("cluster keys list --prefix "..helpers.test_conf.prefix)
      assert.True(ok)
    end)
    it("install key", function()
      local ok = helpers.kong_exec("cluster keys install d7rHSZRrb2FPyJgdBAXMZQ== --prefix "..helpers.test_conf.prefix)
      assert.True(ok)
    end)
    it("remove key", function()
      local ok = helpers.kong_exec("cluster keys remove d7rHSZRrb2FPyJgdBAXMZQ== --prefix "..helpers.test_conf.prefix)
      assert.True(ok)
    end)
    it("use key", function()
      local ok = helpers.kong_exec("cluster keys use daZ2wnuw+Ql+2hCm7vQB6A== --prefix "..helpers.test_conf.prefix)
      assert.True(ok)
    end)

    describe("errors", function()
      it("fails to install an invalid key", function()
        local ok = helpers.kong_exec("cluster keys install helloworld --prefix "..helpers.test_conf.prefix)
        assert.False(ok)
      end)
    end)
  end)

  describe("errors", function()
    it("fails to show members when Kong is not running", function()
      local ok, stderr = helpers.kong_exec("cluster members --prefix "..helpers.test_conf.prefix)
      assert.False(ok)
      assert.matches("Error connecting to Serf agent", stderr)
    end)
    it("fails to show reachability when Kong is not running", function()
      local ok, stderr = helpers.kong_exec("cluster reachability --prefix "..helpers.test_conf.prefix)
      assert.False(ok)
      assert.matches("Error connecting to Serf agent", stderr)
    end)
    it("fails to force-leave when a node is not specified", function()
      local ok, stderr = helpers.kong_exec("cluster force-leave --prefix "..helpers.test_conf.prefix)
      assert.False(ok)
      assert.matches("must specify the name of the node to leave", stderr)
    end)
  end)
end)
