local helpers = require "spec.helpers"
local signals = require "kong.cmd.utils.nginx_signals"
local shell = require "resty.shell"


local fmt = string.format


local TEST_PREFIX = "servroot_prepared_test"


describe("kong prepare", function()
  lazy_setup(function()
    pcall(helpers.dir.rmtree, TEST_PREFIX)
  end)

  after_each(function()
    pcall(helpers.dir.rmtree, TEST_PREFIX)
  end)

  it("prepares a prefix", function()
    assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path, {
      prefix = TEST_PREFIX
    }))
    assert.truthy(helpers.path.exists(TEST_PREFIX))

    local process_secrets = helpers.path.join(TEST_PREFIX, ".kong_process_secrets")
    local admin_access_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_access_log)
    local admin_error_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_error_log)

    assert.falsy(helpers.path.exists(process_secrets))
    assert.truthy(helpers.path.exists(admin_access_log_path))
    assert.truthy(helpers.path.exists(admin_error_log_path))
  end)

  it("prepares a prefix and creates a process secrets file", function()
    helpers.setenv("PG_USER", "test-user")
    finally(function()
      helpers.unsetenv("PG_USER")
    end)
    assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path, {
      prefix = TEST_PREFIX,
      pg_user = "{vault://env/pg-user}",
    }))
    assert.truthy(helpers.path.exists(TEST_PREFIX))

    local process_secrets = helpers.path.join(TEST_PREFIX, ".kong_process_secrets")
    local admin_access_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_access_log)
    local admin_error_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_error_log)

    assert.truthy(helpers.path.exists(process_secrets))
    assert.truthy(helpers.path.exists(admin_access_log_path))
    assert.truthy(helpers.path.exists(admin_error_log_path))
  end)

  it("prepares a prefix from CLI arg option", function()
    assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path ..
                             " -p " .. TEST_PREFIX))
    assert.truthy(helpers.path.exists(TEST_PREFIX))

    local admin_access_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_access_log)
    local admin_error_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_error_log)

    assert.truthy(helpers.path.exists(admin_access_log_path))
    assert.truthy(helpers.path.exists(admin_error_log_path))
  end)

  describe("errors", function()
    it("on inexistent Kong conf file", function()
      local ok, stderr = helpers.kong_exec "prepare --conf foobar.conf"
      assert.False(ok)
      assert.is_string(stderr)
      assert.matches("Error: no file at: foobar.conf", stderr, nil, true)
    end)

    it("on invalid nginx directive", function()
      local ok, stderr = helpers.kong_exec("prepare --conf spec/fixtures/invalid_nginx_directives.conf" ..
                                           " -p " .. TEST_PREFIX)
      assert.False(ok)
      assert.is_string(stderr)
      assert.matches("[emerg] unknown directive \"random_directive\"", stderr,
                     nil, true)
    end)
  end)

  for _, strategy in helpers.each_strategy({ "postgres" }) do
    describe("and start", function()
      lazy_setup(function()
        helpers.get_db_utils(strategy, { "routes" })
      end)
      after_each(function()
        helpers.stop_kong(TEST_PREFIX)
      end)
      it("prepares a prefix and starts kong correctly [#" .. strategy .. "]", function()
        helpers.setenv("PG_DATABASE", "kong")
        finally(function()
          helpers.unsetenv("PG_DATABASE")
        end)
        assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path, {
          prefix = TEST_PREFIX,
          database = strategy,
          pg_database = "{vault://env/pg-database}",
        }))
        assert.truthy(helpers.path.exists(TEST_PREFIX))

        local process_secrets = helpers.path.join(TEST_PREFIX, ".kong_process_secrets")
        local admin_access_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_access_log)
        local admin_error_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_error_log)

        assert.truthy(helpers.path.exists(process_secrets))
        assert.truthy(helpers.path.exists(admin_access_log_path))
        assert.truthy(helpers.path.exists(admin_error_log_path))

        local nginx_bin, err = signals.find_nginx_bin()
        assert.is_nil(err)

        local cmd = fmt("%s -p %s -c %s", nginx_bin, TEST_PREFIX, "nginx.conf")
        local ok, _, stderr = shell.run(cmd, nil, 0)

        assert.equal("", stderr)
        assert.truthy(ok)
        local admin_client = helpers.admin_client()
        local res = admin_client:get("/routes")
        assert.res_status(200, res)
        admin_client:close()
      end)

      it("prepares a prefix and fails to start kong correctly [#" .. strategy .. "]", function()
        helpers.setenv("PG_DATABASE", "kong_tests_unknown")
        finally(function()
          helpers.unsetenv("PG_DATABASE")
        end)
        assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path, {
          prefix = TEST_PREFIX,
          database = strategy,
          pg_database = "{vault://env/pg-database}",
        }))
        assert.truthy(helpers.path.exists(TEST_PREFIX))

        local process_secrets = helpers.path.join(TEST_PREFIX, ".kong_process_secrets")
        local admin_access_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_access_log)
        local admin_error_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_error_log)

        assert.truthy(helpers.path.exists(process_secrets))
        assert.truthy(helpers.path.exists(admin_access_log_path))
        assert.truthy(helpers.path.exists(admin_error_log_path))

        local nginx_bin, err = signals.find_nginx_bin()
        assert.is_nil(err)

        local cmd = fmt("%s -p %s -c %s", nginx_bin, TEST_PREFIX, "nginx.conf")
        local ok, _, stderr = shell.run(cmd, nil, 0)

        assert.matches("kong_tests_unknown", stderr)
        assert.falsy(ok)
      end)
    end)
  end
end)
