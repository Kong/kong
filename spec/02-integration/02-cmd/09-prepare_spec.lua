-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local signals = require "kong.cmd.utils.nginx_signals"
local shell = require "resty.shell"
local ssl_fixtures = require "spec.fixtures.ssl"


local fmt = string.format


local TEST_PREFIX = "servroot_prepared_test"

-- XXX EE workaround for license warning madness
local function assert_no_stderr(logs)

  for line in logs:gmatch("[^\r\n]+") do
    if not line:find("portal and vitals are deprecated") then 
      assert.truthy(
        line:find("Using development (e.g. not a release) license validation", nil, true),
        "expected no stderr, found:\n" .. tostring(line)
      )
    end
  end
end

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

    local process_secrets = helpers.path.join(TEST_PREFIX, ".kong_process_secrets_http")
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

        local process_secrets = helpers.path.join(TEST_PREFIX, ".kong_process_secrets_http")
        local admin_access_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_access_log)
        local admin_error_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_error_log)

        assert.truthy(helpers.path.exists(process_secrets))
        assert.truthy(helpers.path.exists(admin_access_log_path))
        assert.truthy(helpers.path.exists(admin_error_log_path))

        local nginx_bin, err = signals.find_nginx_bin()
        assert.is_nil(err)

        local cmd = fmt("%s -p %s -c %s", nginx_bin, TEST_PREFIX, "nginx.conf")
        local ok, _, stderr = shell.run(cmd, nil, 0)

        assert_no_stderr(stderr)
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

        local process_secrets = helpers.path.join(TEST_PREFIX, ".kong_process_secrets_http")
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

      it("prepares a prefix and starts kong with http and stream submodule correctly [#" .. strategy .. "]", function ()
        helpers.setenv("CERT", ssl_fixtures.cert)
        helpers.setenv("KEY", ssl_fixtures.key)
        helpers.setenv("CERT_ALT", ssl_fixtures.cert_alt)
        helpers.setenv("KEY_ALT", ssl_fixtures.key_alt)
        helpers.setenv("LOGLEVEL", "error")
        finally(function()
          helpers.unsetenv("CERT")
          helpers.unsetenv("CERT_ALT")
          helpers.unsetenv("KEY")
          helpers.unsetenv("KEY_ALT")
          helpers.unsetenv("LOGLEVEL")
        end)
        assert(helpers.kong_exec("prepare -c " .. helpers.test_conf_path, {
          prefix = TEST_PREFIX,
          database = strategy,
          loglevel = "{vault://env/loglevel}",
          lua_ssl_trusted_certificate = "{vault://env/cert}, system",
          ssl_cert_key = "{vault://env/key}, {vault://env/key_alt}",
          ssl_cert = "{vault://env/cert}, {vault://env/cert_alt}",
          vaults = "env",
          proxy_listen = "127.0.0.1:8000",
          stream_listen = "127.0.0.1:9000",
          admin_listen  = "127.0.0.1:8001",
        }))
        assert.truthy(helpers.path.exists(TEST_PREFIX))

        local process_secrets_http = helpers.path.join(TEST_PREFIX, ".kong_process_secrets_http")
        local process_secrets_stream = helpers.path.join(TEST_PREFIX, ".kong_process_secrets_stream")

        local admin_access_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_access_log)
        local admin_error_log_path = helpers.path.join(TEST_PREFIX, helpers.test_conf.admin_error_log)

        assert.truthy(helpers.path.exists(process_secrets_http))
        assert.truthy(helpers.path.exists(process_secrets_stream))
        assert.truthy(helpers.path.exists(admin_access_log_path))
        assert.truthy(helpers.path.exists(admin_error_log_path))

        local nginx_bin, err = signals.find_nginx_bin()
        assert.is_nil(err)

        local cmd = fmt("%s -p %s -c %s", nginx_bin, TEST_PREFIX, "nginx.conf")
        local ok, _, stderr = shell.run(cmd, nil, 0)

        assert.equal("", stderr)
        assert.truthy(ok)
        local error_log_path = helpers.path.join(TEST_PREFIX, "logs/error.log")
        assert.logfile(error_log_path).has.no.line("[error]", true, 0)
        assert.logfile(error_log_path).has.no.line("[alert]", true, 0)
        assert.logfile(error_log_path).has.no.line("[crit]",  true, 0)
        assert.logfile(error_log_path).has.no.line("[emerg]", true, 0)
        assert
        .with_timeout(5)
        .ignore_exceptions(true)
        .eventually(function()
          local client = helpers.admin_client(nil, 8001)
          local res, err = client:send({ path = "/status", method = "GET" })

          if res then res:read_body() end

          client:close()

          if not res then
            return nil, err
          end

          if res.status ~= 200 then
            return nil, res
          end

          return true
        end)
        .is_truthy("/status API did not return 200")
      end)
    end)
  end
end)
