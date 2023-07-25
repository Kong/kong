-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
    assert.matches("Error: could not find vault (none)", stderr, nil, true)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("vault get with non-existing key", function()
    local ok, stderr, stdout = helpers.kong_exec("vault get env/none")
    assert.matches("could not get value from external vault", stderr, nil, true)
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

  for _, strategy in helpers.each_strategy({ "postgres"}) do
    describe("[env] instantiated #" .. strategy, function()
      local admin_client
      lazy_setup(function()
        helpers.get_db_utils(strategy, {
          "vaults"
        })

        assert(helpers.start_kong({
          database   = strategy,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        admin_client = helpers.admin_client()
        local res = admin_client:put("/vaults/test-env", {
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
