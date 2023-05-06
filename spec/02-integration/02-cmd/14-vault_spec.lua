local helpers = require "spec.helpers"


for _, strategy in helpers.all_strategies() do
describe("kong vault #" .. strategy, function()
  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
  end)

  lazy_teardown(function()
    helpers.clean_prefix()
  end)

  it("vault help", function()
    local ok, stderr, stdout = helpers.kong_exec("vault --help", {
      prefix = helpers.test_conf.prefix,
    })
    assert.matches("Usage: kong vault COMMAND [OPTIONS]", stderr, nil, true)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("vault get without params", function()
    local ok, stderr, stdout = helpers.kong_exec("vault get", {
      prefix = helpers.test_conf.prefix,
    })
    assert.matches("Error: the 'get' command needs a <reference> argument", stderr)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("vault get with non-existing vault", function()
    local ok, stderr, stdout = helpers.kong_exec("vault get none/foo", {
      prefix = helpers.test_conf.prefix,
    })
    assert.matches("Error: vault not found (none)", stderr, nil, true)
    assert.matches("[{vault://none/foo}]", stderr, nil, true)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("vault get with non-existing key", function()
    local ok, stderr, stdout = helpers.kong_exec("vault get env/none", {
      prefix = helpers.test_conf.prefix,
    })
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
      local ok, stderr, stdout = helpers.kong_exec("vault get env/secrets_test", {
        prefix = helpers.test_conf.prefix,
      })
      assert.equal("", stderr)
      assert.matches("testvalue", stdout, nil, true)
      assert.is_true(ok)

      ok, stderr, stdout = helpers.kong_exec("vault get env/secrets-test", {
        prefix = helpers.test_conf.prefix,
      })
      assert.equal("", stderr)
      assert.matches("testvalue", stdout, nil, true)
      assert.is_true(ok)
    end)

    it("vault get env with config", function()
      finally(function()
        helpers.unsetenv("KONG_VAULT_ENV_PREFIX")
        helpers.unsetenv("SECRETS_TEST")
      end)
      helpers.setenv("KONG_VAULT_ENV_PREFIX", "SECRETS_")
      helpers.setenv("SECRETS_TEST", "testvalue-with-config")
      local ok, stderr, stdout = helpers.kong_exec("vault get env/test", {
        prefix = helpers.test_conf.prefix,
      })
      assert.equal("", stderr)
      assert.matches("testvalue-with-config", stdout, nil, true)
      assert.is_true(ok)
    end)

    it("vault get env with config with dash", function()
      finally(function()
        helpers.unsetenv("KONG_VAULT_ENV_PREFIX")
        helpers.unsetenv("SECRETS_AGAIN_TEST")
      end)
      helpers.setenv("KONG_VAULT_ENV_PREFIX", "SECRETS-AGAIN-")
      helpers.setenv("SECRETS_AGAIN_TEST_TOO", "testvalue-with-config-again")
      local ok, stderr, stdout = helpers.kong_exec("vault get env/test-too", {
        prefix = helpers.test_conf.prefix,
      })
      assert.equal("", stderr)
      assert.matches("testvalue-with-config-again", stdout, nil, true)
      assert.is_true(ok)
    end)
  end)

  describe("[env] instantiated #" .. strategy, function()
    local db, _, yaml_file
    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, {
        "vaults"
      })

      db.vaults:insert {
        prefix = "test-env",
        name = "env",
        config = {
          prefix = "SECRETS_",
        }
      }

      yaml_file = helpers.make_yaml_file([[
        _format_version: "3.0"
        vaults:
        - config:
            prefix: SECRETS_
          name: env
          prefix: test-env
      ]])

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        declarative_config = yaml_file,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("vault get env", function()
      finally(function()
        helpers.unsetenv("SECRETS_TEST")
      end)
      helpers.setenv("SECRETS_TEST", "testvalue")
      ngx.sleep(3)

      -- will fail without directives injected
      local ok, stderr, stdout = helpers.kong_exec("vault get test-env/test --no-inject", {
        prefix = helpers.test_conf.prefix,
      })
      assert.matches("unable to open DB for access: no LMDB environment defined", stderr, nil, true)
      assert.matches("[{vault://test-env/nonexist}]", stderr, nil, true)
      assert.is_nil(stdout)
      assert.is_false(ok)

      -- will succeed with directives injected
      local ok, stderr, stdout = helpers.kong_exec("vault get test-env/test", {
        prefix = helpers.test_conf.prefix,
      })
      assert.equal("", stderr)
      assert.matches("testvalue", stdout)
      assert.is_true(ok)
    end)

    it("vault get non-existing env", function()
      local ok, stderr, stdout = helpers.kong_exec("vault get test-env/nonexist", {
        prefix = helpers.test_conf.prefix,
      })
      assert.matches("Error: unable to load value (nonexist) from vault (test-env): not found", stderr, nil, true)
      assert.matches("[{vault://test-env/nonexist}]", stderr, nil, true)
      assert.is_nil(stdout)
      assert.is_false(ok)
    end)

    it("vault get non-existing vault", function()
      local ok, stderr, stdout = helpers.kong_exec("vault get nonexist/nonexist", {
        prefix = helpers.test_conf.prefix,
      })
      assert.matches("Error: vault not found (nonexist)", stderr, nil, true)
      assert.matches("[{vault://nonexist/nonexist}]", stderr, nil, true)
      assert.is_nil(stdout)
      assert.is_false(ok)
    end)
  end)
end)
end
