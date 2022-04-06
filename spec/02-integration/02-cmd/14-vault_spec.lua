local helpers = require "spec.helpers"


describe("kong vault", function()
  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
  end)

  after_each(function()
    helpers.kill_all()
  end)

  lazy_teardown(function()
    helpers.clean_prefix()
  end)

  it("vault help", function()
    local ok, stderr, stdout = helpers.kong_exec("vault --help")
    assert.matches("Usage: kong vault COMMAND [OPTIONS]", stderr, nil, true)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("vault get without params", function()
    local ok, stderr, stdout = helpers.kong_exec("vault get")
    assert.matches("Error: the 'get' command needs a <reference> argument", stderr)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("vault get with non-existing vault", function()
    local ok, stderr, stdout = helpers.kong_exec("vault get none/foo")
    assert.matches("Error: vault not found (none)", stderr, nil, true)
    assert.matches("[{vault://none/foo}]", stderr, nil, true)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("vault get with non-existing key", function()
    local ok, stderr, stdout = helpers.kong_exec("vault get env/none", { vaults = "env"})
    assert.matches("Error: unable to load value (none) from vault (env): not found [{vault://env/none}]", stderr, nil, true)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  describe("[env] uninstantiated secrets", function()
    it("vault get env", function()
      finally(function()
        helpers.unsetenv("SECRETS_TEST")
      end)
      helpers.setenv("SECRETS_TEST", "testvalue")
      local ok, stderr, stdout = helpers.kong_exec("vault get env/secrets_test", { vaults = "env" })
      assert.equal("", stderr)
      assert.matches("testvalue", stdout)
      assert.is_true(ok)
    end)
  end)

  for _, strategy in helpers.each_strategy({ "postgres", "cassandra "}) do
    describe("[env] instantiated #" .. strategy, function()
      local admin_client
      lazy_setup(function()
        helpers.get_db_utils(strategy, {
          "vaults_beta"
        })

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
          vaults = "env",
        }))

        admin_client = helpers.admin_client()
        local res = admin_client:put("/vaults-beta/test-env", {
          headers = {
            ["Content-Type"] = "application/json"
          },
          body = {
            name = "env",
            config = {
              prefix = "SECRETS_"
            },
          }
        })

        assert.res_status(200, res)
      end)

      lazy_teardown(function()
        if admin_client then
          admin_client:close()
        end

        helpers.stop_kong()
      end)

      it("vault get env", function()
        finally(function()
          helpers.unsetenv("SECRETS_TEST")
        end)
        helpers.setenv("SECRETS_TEST", "testvalue")
        ngx.sleep(3)
        local ok, stderr, stdout = helpers.kong_exec("vault get test-env/test", {
          prefix = helpers.test_conf.prefix,
        })
        assert.equal("", stderr)
        assert.matches("testvalue", stdout)
        assert.is_true(ok)
      end)
    end)
  end
end)
