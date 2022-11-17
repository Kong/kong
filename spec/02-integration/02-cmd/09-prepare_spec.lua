local kong_constants = require "kong.constants"
local helpers = require "spec.helpers"
local signals = require "kong.cmd.utils.nginx_signals"
local pl_utils = require "pl.utils"


local fmt = string.format


local TEST_PREFIX = "servroot_prepared_test"
local LMDB_DIRECTORY = kong_constants.LMDB_DIRECTORY


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

  it("prepares a directory for LMDB with a special config.nginx_user", function()
    local _, _, user  = pl_utils.executeex("whoami")
    user = user:sub(1, -2)  -- strip '\n'

    assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path, {
                              prefix = TEST_PREFIX,
                              nginx_user = user,
                              }))
    assert.truthy(helpers.path.exists(TEST_PREFIX))

    local lmdb_data_path = helpers.path.join(TEST_PREFIX, LMDB_DIRECTORY .. "/data.mdb")
    local lmdb_lock_path = helpers.path.join(TEST_PREFIX, LMDB_DIRECTORY .. "/lock.mdb")

    assert.truthy(helpers.path.exists(lmdb_data_path))
    assert.truthy(helpers.path.exists(lmdb_lock_path))

    local handle = io.popen("ls -l " .. TEST_PREFIX .. " | grep " .. LMDB_DIRECTORY)
    local result = handle:read("*a")
    handle:close()
    assert.matches("drwx------", result, nil, true)
    assert.matches(user, result, nil, true)

    local handle = io.popen("ls -l " .. lmdb_data_path)
    local result = handle:read("*a")
    handle:close()
    assert.matches("-rw-------", result, nil, true)
    assert.matches(user, result, nil, true)

    local handle = io.popen("ls -l " .. lmdb_lock_path)
    local result = handle:read("*a")
    handle:close()
    assert.matches("-rw-------", result, nil, true)
    assert.matches(user, result, nil, true)
  end)

  it("will not create directory for LMDB if no config.nginx_user", function()
    assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path, {
                              prefix = TEST_PREFIX,
                              nginx_user = nil,
                              }))
    assert.truthy(helpers.path.exists(TEST_PREFIX))

    local lmdb_path = helpers.path.join(TEST_PREFIX, LMDB_DIRECTORY)

    assert.falsy(helpers.path.exists(lmdb_path))
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
        local ok, _, _, stderr = pl_utils.executeex(cmd)

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
        local ok, _, _, stderr = pl_utils.executeex(cmd)

        assert.matches("kong_tests_unknown", stderr)
        assert.falsy(ok)
      end)
    end)
  end
end)
