local helpers   = require "spec.helpers"
local constants = require "kong.constants"
local pl_file   = require("pl.file")

local cjson = require "cjson"

local fmt = string.format
local kong_exec = helpers.kong_exec
local read_file = helpers.file.read


local PREFIX = helpers.test_conf.prefix
local TEST_CONF = helpers.test_conf
local TEST_CONF_PATH = helpers.test_conf_path


local function wait_until_healthy(prefix)
  prefix = prefix or PREFIX

  local cmd

  -- use `kong-health` if available
  if helpers.path.exists(helpers.bin_path .. "-health") then
    cmd = fmt("%s-health -p %q", helpers.bin_path, prefix)
  else
    cmd = fmt("%s health -p %q", helpers.bin_path, prefix)
  end

  assert
    .with_timeout(10)
    .eventually(function()
      local ok, code, stdout, stderr = helpers.execute(cmd, true)
      if not ok then
        return nil, { code = code, stdout = stdout, stderr = stderr }
      end

      return true
    end)
    .is_truthy("expected `" .. cmd .. "` to succeed")

  local conf = assert(helpers.get_running_conf(prefix))

  if conf.proxy_listen and conf.proxy_listen ~= "off" then
    helpers.wait_for_file("socket", prefix .. "/worker_events.sock")
  end

  if conf.stream_listen and conf.stream_listen ~= "off" then
    helpers.wait_for_file("socket", prefix .. "/stream_worker_events.sock")
  end

  if conf.admin_listen and conf.admin_listen ~= "off" then
    local port = assert(conf.admin_listen:match(":([0-9]+)"))
    assert
      .with_timeout(5)
      .eventually(function()
        local client = helpers.admin_client(1000, port)
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
  end
end


for _, strategy in helpers.each_strategy() do

describe("kong start/stop #" .. strategy, function()
  local proxy_client, admin_client

  lazy_setup(function()
    helpers.get_db_utils(strategy) -- runs migrations
    helpers.prepare_prefix()
  end)

  after_each(function()
    if proxy_client then
      proxy_client:close()
    end

    if admin_client then
      admin_client:close()
    end

    helpers.stop_kong()
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  it("fails with referenced values that are not initialized", function()
    local ok, stderr, stdout = kong_exec("start", {
      prefix = PREFIX,
      database = strategy,
      nginx_proxy_real_ip_header = "{vault://env/ipheader}",
      pg_database = TEST_CONF.pg_database,
      vaults = "env",
    })

    assert.matches("vault://env/ipheader", stderr, nil, true)
    assert.matches("Error: failed to dereference '{vault://env/ipheader}'", stderr)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("fails to read referenced secrets when vault does not exist", function()
    local ok, stderr, stdout = kong_exec("start", {
      prefix = PREFIX,
      database = TEST_CONF.database,
      pg_password = "{vault://non-existent/pg_password}",
      pg_database = TEST_CONF.pg_database,
    })

    assert.matches("Error: failed to dereference", stderr, nil, true)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("resolves referenced secrets", function()
    helpers.clean_logfile()
    helpers.setenv("PG_PASSWORD", "dummy")

    local _, stderr, stdout = assert(kong_exec("start", {
      prefix = PREFIX,
      database = TEST_CONF.database,
      pg_password = "{vault://env/pg_password}",
      pg_database = TEST_CONF.pg_database,
      vaults = "env",
    }))

    assert.not_matches("failed to dereference {vault://env/pg_password}", stderr, nil, true)
    assert.logfile().has.no.line("[warn]", true)
    assert.logfile().has.no.line("env/pg_password", true)
    assert.matches("Kong started", stdout, nil, true)
    assert(kong_exec("stop", {
      prefix = PREFIX,
    }))
  end)

  it("start help", function()
    local _, stderr = kong_exec "start --help"
    assert.not_equal("", stderr)
  end)

  it("stop help", function()
    local _, stderr = kong_exec "stop --help"
    assert.not_equal("", stderr)
  end)

  it("start/stop gracefully with default conf/prefix", function()
    assert(kong_exec("start", {
      prefix = PREFIX,
      database = TEST_CONF.database,
      pg_database = TEST_CONF.pg_database,
    }))

    assert(kong_exec("stop", { prefix = PREFIX }))
  end)

  it("start/stop stops without error when references cannot be resolved", function()
    helpers.setenv("PG_PASSWORD", "dummy")

    local _, stderr, stdout = assert(kong_exec("start", {
      prefix = PREFIX,
      database = TEST_CONF.database,
      pg_password = "{vault://env/pg_password}",
      pg_database = TEST_CONF.pg_database,
      vaults = "env",
    }))

    assert.not_matches("failed to dereference {vault://env/pg_password}", stderr, nil, true)
    assert.matches("Kong started", stdout, nil, true)

    helpers.unsetenv("PG_PASSWORD")

    local _, stderr, stdout = assert(kong_exec("stop", {
      prefix = PREFIX,
    }))

    assert.not_matches("failed to dereference {vault://env/pg_password}", stderr, nil, true)
    assert.matches("Kong stopped", stdout, nil, true)
  end)

  it("start/stop custom Kong conf/prefix", function()
    assert(kong_exec("start --conf " .. TEST_CONF_PATH))
    assert(kong_exec("stop --prefix " .. PREFIX))
  end)

  it("stop honors custom Kong prefix higher than environment variable", function()
    assert(kong_exec("start --conf " .. TEST_CONF_PATH))

    helpers.setenv("KONG_PREFIX", "/tmp/dne")
    finally(function() helpers.unsetenv("KONG_PREFIX") end)

    assert(kong_exec("stop --prefix " .. PREFIX))
  end)

  it("start/stop Kong with only stream listeners enabled", function()
    assert(kong_exec("start ", {
      prefix = PREFIX,
      admin_listen = "off",
      proxy_listen = "off",
      stream_listen = "127.0.0.1:9022",
    }))

    wait_until_healthy()

    assert(kong_exec("stop", { prefix = PREFIX }))
  end)

  it("start dumps Kong config in prefix", function()
    assert(kong_exec("start --conf " .. TEST_CONF_PATH))
    assert.truthy(helpers.path.exists(TEST_CONF.kong_env))
  end)

  it("should not add [emerg], [alert], [crit], [error] or [warn] lines to error log", function()
    helpers.clean_logfile()
    assert(helpers.kong_exec("start ", {
      prefix = helpers.test_conf.prefix,
      stream_listen = "127.0.0.1:9022",
      status_listen = "0.0.0.0:8100",
    }))
    ngx.sleep(0.1)   -- wait unix domain socket
    assert(helpers.kong_exec("stop", {
      prefix = helpers.test_conf.prefix
    }))

    assert.logfile().has.no.line("[emerg]", true)
    assert.logfile().has.no.line("[alert]", true)
    assert.logfile().has.no.line("[crit]", true)
    assert.logfile().has.no.line("[error]", true)
    assert.logfile().has.no.line("[warn]", true)
  end)

  it("creates prefix directory if it doesn't exist", function()
    finally(function()
      -- this test uses a non-default prefix, so it must manage
      -- its kong instance directly
      helpers.stop_kong("foobar")
    end)

    assert.falsy(helpers.path.exists("foobar"))
    assert(kong_exec("start --prefix foobar", {
      pg_database = TEST_CONF.pg_database,
    }))
    assert.truthy(helpers.path.exists("foobar"))
  end)

  describe("verbose args", function()
    it("accepts verbose --v", function()
      local _, _, stdout = assert(kong_exec("start --v --conf " .. TEST_CONF_PATH))
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
    end)

    it("accepts debug --vv", function()
      local _, _, stdout = assert(kong_exec("start --vv --conf " .. TEST_CONF_PATH))
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
      assert.matches("[debug] prefix = ", stdout, nil, true)
      assert.matches("[debug] database = ", stdout, nil, true)
    end)

    it("prints ENV variables when detected #postgres", function()
      local _, _, stdout = assert(kong_exec("start --vv --conf " .. TEST_CONF_PATH, {
        database = "postgres",
        admin_listen = "127.0.0.1:8001"
      }))
      assert.matches('KONG_DATABASE ENV found with "postgres"', stdout, nil, true)
      assert.matches('KONG_ADMIN_LISTEN ENV found with "127.0.0.1:8001"', stdout, nil, true)
    end)

    it("prints config in alphabetical order", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf " .. TEST_CONF_PATH))
      assert.matches("admin_listen.*anonymous_reports.*pg_user.*prefix.*", stdout)
    end)

    it("does not print sensitive settings in config", function()
      local _, _, stdout = assert(kong_exec("start --vv --conf " .. TEST_CONF_PATH, {
        pg_password = "do not print",
      }))
      assert.matches('KONG_PG_PASSWORD ENV found with "******"', stdout, nil, true)
      assert.matches('pg_password = "******"', stdout, nil, true)
    end)
  end)

  describe("custom --nginx-conf", function()
    local templ_fixture = "spec/fixtures/custom_nginx.template"

    it("accept a custom Nginx configuration", function()
      assert(kong_exec("start --conf " .. TEST_CONF_PATH .. " --nginx-conf " .. templ_fixture))
      assert.truthy(helpers.path.exists(TEST_CONF.nginx_conf))

      local contents = read_file(TEST_CONF.nginx_conf)
      assert.matches("# This is a custom nginx configuration template for Kong specs", contents, nil, true)
      assert.matches("daemon on;", contents, nil, true)
    end)
  end)

  describe("/etc/hosts resolving in CLI", function()
    if strategy == "postgres" then
      it("resolves #postgres hostname", function()
        assert(kong_exec("start --conf " .. TEST_CONF_PATH, {
          pg_host = "localhost",
          database = "postgres"
        }))
      end)
    end

  end)

  -- TODO: update with new error messages and behavior
  pending("--run-migrations", function()
    before_each(function()
      helpers.dao:drop_schema()
    end)
    after_each(function()
      helpers.dao:drop_schema()
      helpers.dao:run_migrations()
    end)

    describe("errors", function()
      it("does not start with an empty datastore", function()
        local ok, stderr  = kong_exec("start --conf "..TEST_CONF_PATH)
        assert.False(ok)
        assert.matches("the current database schema does not match this version of Kong.", stderr)
      end)

      it("does not start if migrations are not up to date", function()
        helpers.dao:run_migrations()
        -- Delete a migration to simulate inconsistencies between version
        local _, err = helpers.dao.db:query([[
          DELETE FROM schema_migrations WHERE id='rate-limiting'
        ]])
        assert.is_nil(err)

        local ok, stderr  = kong_exec("start --conf "..TEST_CONF_PATH)
        assert.False(ok)
        assert.matches("the current database schema does not match this version of Kong.", stderr)
      end)

      it("connection check errors are prefixed with DB-specific prefix", function()
        local ok, stderr = kong_exec("start --conf " .. TEST_CONF_PATH, {
          pg_port = 99999,
        })
        assert.False(ok)
        assert.matches("[" .. TEST_CONF.database .. " error]", stderr, 1, true)
      end)
    end)
  end)

  describe("nginx_main_daemon = off", function()
    it("redirects nginx's stdout to 'kong start' stdout", function()
      local stdout_path = os.tmpname()

      finally(function()
        os.remove(stdout_path)
      end)

      local cmd = fmt("KONG_PROXY_ACCESS_LOG=/dev/stdout "    ..
                                "KONG_NGINX_MAIN_DAEMON=off %s start -c %s " ..
                                ">%s 2>/dev/null &", helpers.bin_path,
                                TEST_CONF_PATH, stdout_path)

      local ok, _, _, stderr = helpers.execute(cmd, true)
      assert.truthy(ok, stderr)

      wait_until_healthy()

      proxy_client = helpers.proxy_client()

      local res = proxy_client:get("/hello")
      assert.res_status(404, res) -- no Route configured

      -- TEST: since nginx started in the foreground, the 'kong start' command
      -- stdout should receive all of nginx's stdout as well.
      assert.logfile(stdout_path).has.line([["GET /hello HTTP/1.1" 404]], true, 5)
    end)
  end)

  if strategy == "off" then
    describe("declarative config start", function()
      it("starts with a valid declarative config file", function()
        local yaml_file = helpers.make_yaml_file [[
          _format_version: "1.1"
          services:
          - name: my-service
            url: http://127.0.0.1:15555
            routes:
            - name: example-route
              hosts:
              - example.test
        ]]

        finally(function()
          os.remove(yaml_file)
        end)

        assert(helpers.start_kong({
          database = "off",
          declarative_config = yaml_file,
          nginx_worker_processes = 100, -- stress test initialization
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        wait_until_healthy()

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/", {
          headers = { host = "example.test" }
        })

        assert.response(res).has.status(200)
      end)

      it("starts with a valid declarative config string", function()
        local config_string = cjson.encode {
          _format_version = "1.1",
          services =  {
            {
              name = "my-service",
              url = "http://127.0.0.1:15555",
              routes = {
                {
                  name = "example-route",
                  hosts = { "example.test" }
                }
              }
            }
          }
        }

        assert(helpers.start_kong({
          database = "off",
          declarative_config_string = config_string,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        wait_until_healthy()

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/", {
          headers = { host = "example.test" }
        })

        assert.response(res).has.status(200)
      end)

      it("hash is set correctly for a non-empty configuration", function()
        local yaml_file = helpers.make_yaml_file [[
          _format_version: "1.1"
          services:
          - name: my-service
            url: http://127.0.0.1:15555
            routes:
            - name: example-route
              hosts:
              - example.test
        ]]

        finally(function()
          os.remove(yaml_file)
        end)

        assert(helpers.start_kong({
          database = "off",
          declarative_config = yaml_file,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        wait_until_healthy()

        admin_client = helpers.admin_client()
        local res = admin_client:get("/status")

        assert.response(res).has.status(200)

        local json = assert.response(res).has.jsonbody()

        assert.is_string(json.configuration_hash)
        assert.equals(32, #json.configuration_hash)
        assert.not_equal(constants.DECLARATIVE_EMPTY_CONFIG_HASH, json.configuration_hash)
      end)

      it("hash is set correctly for an empty configuration", function()

        -- not specifying declarative_config this time
        assert(helpers.start_kong({
          database = "off",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        wait_until_healthy()

        admin_client = helpers.admin_client()
        local res = admin_client:get("/status")

        assert.response(res).has.status(200)

        local json = assert.response(res).has.jsonbody()

        assert.is_string(json.configuration_hash)
        assert.equals(constants.DECLARATIVE_EMPTY_CONFIG_HASH, json.configuration_hash)
      end)
    end)
  end

  describe("errors", function()
    it("start inexistent Kong conf file", function()
      local ok, stderr = kong_exec "start --conf foobar.conf"
      assert.False(ok)
      assert.is_string(stderr)
      assert.matches("Error: no file at: foobar.conf", stderr, nil, true)
    end)

    it("stop inexistent prefix", function()
      assert(helpers.kong_exec("start --prefix " .. PREFIX, {
        pg_database = TEST_CONF.pg_database,
      }))

      local ok, stderr = kong_exec("stop --prefix inexistent")
      assert.False(ok)
      assert.matches("Error: no such prefix: .*/inexistent", stderr)
    end)

    it("notifies when Kong is already running", function()
      assert(helpers.kong_exec("start --prefix " .. PREFIX, {
        pg_database = TEST_CONF.pg_database,
      }))

      local ok, stderr = kong_exec("start --prefix " .. PREFIX, {
        pg_database = TEST_CONF.pg_database
      })
      assert.False(ok)
      assert.matches("Kong is already running in " .. PREFIX, stderr, nil, true)
    end)

    it("should not start Kong if already running in prefix", function()
      local kill = require "kong.cmd.utils.kill"

      assert(helpers.kong_exec("start --prefix " .. PREFIX, {
        pg_database = TEST_CONF.pg_database,
      }))

      local ok, stderr = kong_exec("start --prefix " .. PREFIX, {
        pg_database = TEST_CONF.pg_database
      })
      assert.False(ok)
      assert.matches("Kong is already running in " .. PREFIX, stderr, nil, true)

      assert(kill.is_running(TEST_CONF.nginx_pid))
    end)

    it("does not prepare the prefix directory if Kong is already running", function()
      assert(kong_exec("start --prefix " .. PREFIX, {
        database = "off",
        nginx_main_worker_processes = "1",
      }))

      local kong_env = PREFIX .. "/.kong_env"

      local before, err = read_file(kong_env)
      assert.truthy(before, "failed reading .kong_env: " .. tostring(err))
      assert.matches("nginx_main_worker_processes = 1", before) -- sanity

      local ok, stderr = kong_exec("start --prefix " .. PREFIX, {
        database = "off",
        nginx_main_worker_processes = "2",
      })

      assert.falsy(ok)
      assert.matches("Kong is already running", stderr)

      local after
      after, err = read_file(kong_env)
      assert.truthy(after, "failed reading .kong_env: " .. tostring(err))

      assert.equal(before, after, ".kong_env file was rewritten")
    end)

    it("ensures the required shared dictionaries are defined", function()
      local tmp_nginx_config = "spec/fixtures/nginx_conf.tmp"
      local prefix_handler = require "kong.cmd.utils.prefix_handler"
      local conf_loader = require "kong.conf_loader"

      local nginx_conf = assert(conf_loader(helpers.test_conf_path, {
        prefix = "servroot_tmp",
      }))
      assert(prefix_handler.prepare_prefix(nginx_conf))
      assert.truthy(helpers.path.exists(nginx_conf.nginx_conf))
      local kong_nginx_conf = assert(prefix_handler.compile_kong_conf(nginx_conf))

      for _, dict in ipairs(constants.DICTS) do
        -- remove shared dictionary entry
        local http_cfg = string.gsub(kong_nginx_conf, "lua_shared_dict%s" .. dict .. "%s.-\n", "")
        local conf = [[pid pids/nginx.pid;
          error_log logs/error.log debug;
          daemon on;
          worker_processes 1;
          events {
            multi_accept off;
          }
          http {
            ]]
            .. http_cfg ..
            [[
          }
        ]]

        pl_file.write(tmp_nginx_config, conf)
        local ok, err = helpers.start_kong({ nginx_conf = tmp_nginx_config })
        assert.falsy(ok)
        assert.matches(
          "missing shared dict '" .. dict .. "' in Nginx configuration, "    ..
          "are you using a custom template? Make sure the 'lua_shared_dict " ..
          dict .. " [SIZE];' directive is defined.", err, nil, true)
      end

      finally(function()
        os.remove(tmp_nginx_config)
      end)
    end)

    if strategy == "off" then
      it("does not start with an invalid declarative config file", function()
        helpers.clean_logfile()

        local yaml_file = helpers.make_yaml_file [[
          _format_version: "1.1"
          services:
          - name: "@gobo"
            protocol: foo
            host: mockbin.org
          - name: my-service
            url: http://mockbin.org
            routes:
            - name: example-route
              hosts:
              - example.test
              - \\99
        ]]

        finally(function()
          os.remove(yaml_file)
        end)

        local ok, err = helpers.start_kong({
          database = "off",
          declarative_config = yaml_file,
        })

        assert.falsy(ok)
        assert.matches("in 'protocol': expected one of: grpc, grpcs, http, https, tcp, tls, tls_passthrough, udp", err, nil, true)
        assert.matches("in 'name': invalid value '@gobo': the only accepted ascii characters are alphanumerics or ., -, _, and ~", err, nil, true)
        assert.matches("in entry 2 of 'hosts': invalid hostname: \\\\99", err, nil, true)
      end)

      it("dbless can reference secrets in declarative configuration", function()
        helpers.clean_logfile()
        helpers.setenv("SESSION_SECRET", "top-secret-value")

        local yaml_file = helpers.make_yaml_file [[
          _format_version: "3.0"
          _transform: true
          plugins:
          - name: session
            instance_name: session
            config:
              secret: "{vault://mocksocket/session-secret}"
        ]]

        finally(function()
          helpers.unsetenv("SESSION_SECRET")
          os.remove(yaml_file)
        end)

        helpers.setenv("KONG_LUA_PATH_OVERRIDE", "./spec/fixtures/custom_vaults/?.lua;./spec/fixtures/custom_vaults/?/init.lua;;")
        helpers.get_db_utils(strategy, {
          "vaults",
        }, {
          "session"
        }, {
          "mocksocket"
        })

        local ok, err = helpers.start_kong({
          database = "off",
          declarative_config = yaml_file,
          vaults = "mocksocket",
          plugins = "session",
        })

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)

        assert.truthy(ok)
        assert.not_matches("error", err)
        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.no.line(" {vault://mocksocket/session-secret}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        assert(helpers.restart_kong({
          database = "off",
          vaults = "mocksocket",
          plugins = "session",
          declarative_config = "",
        }))

        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.no.line(" {vault://mocksocket/session-secret}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)

        assert(helpers.reload_kong("off", "reload --prefix " .. helpers.test_conf.prefix, {
          database = "off",
          vaults = "mocksocket",
          plugins = "session",
          declarative_config = "",
        }))

        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.no.line(" {vault://mocksocket/session-secret}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)

      end)

      it("dbless does not fail fatally when referencing secrets doesn't work in declarative configuration", function()
        helpers.clean_logfile()

        local yaml_file = helpers.make_yaml_file [[
          _format_version: "3.0"
          _transform: true
          plugins:
          - name: session
            instance_name: session
            config:
              secret: "{vault://mocksocket/session-secret-unknown}"
        ]]

        finally(function()
          os.remove(yaml_file)
        end)

        helpers.setenv("KONG_LUA_PATH_OVERRIDE", "./spec/fixtures/custom_vaults/?.lua;./spec/fixtures/custom_vaults/?/init.lua;;")
        helpers.get_db_utils(strategy, {
          "vaults",
        }, {
          "session"
        }, {
          "mocksocket"
        })

        local ok, err = helpers.start_kong({
          database = "off",
          declarative_config = yaml_file,
          vaults = "mocksocket",
          plugins = "session",
        })

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)

        assert.truthy(ok)
        assert.not_matches("error", err)
        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.line(" {vault://mocksocket/session-secret-unknown}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        assert(helpers.restart_kong({
          database = "off",
          vaults = "mocksocket",
          plugins = "session",
          declarative_config = "",
        }))

        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.line(" {vault://mocksocket/session-secret-unknown}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)

        assert(helpers.reload_kong("off", "reload --prefix " .. helpers.test_conf.prefix, {
          database = "off",
          vaults = "mocksocket",
          plugins = "session",
          declarative_config = "",
        }))

        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.line(" {vault://mocksocket/session-secret-unknown}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)
      end)

      it("dbless can reference secrets in declarative configuration using vault entities", function()
        helpers.clean_logfile()
        helpers.setenv("SESSION_SECRET_AGAIN", "top-secret-value")

        local yaml_file = helpers.make_yaml_file [[
          _format_version: "3.0"
          _transform: true
          plugins:
          - name: session
            instance_name: session
            config:
              secret: "{vault://mock/session-secret-again}"
          vaults:
          - description: my vault
            name: mocksocket
            prefix: mock
        ]]

        finally(function()
          helpers.unsetenv("SESSION_SECRET_AGAIN")
          os.remove(yaml_file)
        end)

        helpers.setenv("KONG_LUA_PATH_OVERRIDE", "./spec/fixtures/custom_vaults/?.lua;./spec/fixtures/custom_vaults/?/init.lua;;")
        helpers.get_db_utils(strategy, {
          "vaults",
        }, {
          "session"
        }, {
          "mocksocket"
        })

        local ok, err = helpers.start_kong({
          database = "off",
          declarative_config = yaml_file,
          vaults = "mocksocket",
          plugins = "session",
        })

        assert.truthy(ok)
        assert.not_matches("error", err)
        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.no.line(" {vault://mock/session-secret-again}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)

        assert(helpers.restart_kong({
          database = "off",
          vaults = "mocksocket",
          plugins = "session",
          declarative_config = "",
        }))

        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.no.line(" {vault://mock/session-secret-again}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)

        assert(helpers.reload_kong("off", "reload --prefix " .. helpers.test_conf.prefix, {
          database = "off",
          vaults = "mocksocket",
          plugins = "session",
          declarative_config = "",
        }))

        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.no.line(" {vault://mock/session-secret-again}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)
      end)

      it("dbless does not fail fatally when referencing secrets doesn't work in declarative configuration using vault entities", function()
        helpers.clean_logfile()

        local yaml_file = helpers.make_yaml_file [[
          _format_version: "3.0"
          _transform: true
          plugins:
          - name: session
            instance_name: session
            config:
              secret: "{vault://mock/session-secret-unknown-again}"
          vaults:
          - description: my vault
            name: mocksocket
            prefix: mock
        ]]

        finally(function()
          os.remove(yaml_file)
        end)

        helpers.setenv("KONG_LUA_PATH_OVERRIDE", "./spec/fixtures/custom_vaults/?.lua;./spec/fixtures/custom_vaults/?/init.lua;;")
        helpers.get_db_utils(strategy, {
          "vaults",
        }, {
          "session"
        }, {
          "mocksocket"
        })

        local ok, err = helpers.start_kong({
          database = "off",
          declarative_config = yaml_file,
          vaults = "mocksocket",
          plugins = "session",
        })

        assert.truthy(ok)
        assert.not_matches("error", err)
        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.line(" {vault://mock/session-secret-unknown-again}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)

        assert(helpers.restart_kong({
          database = "off",
          vaults = "mocksocket",
          plugins = "session",
          declarative_config = "",
        }))

        assert.logfile().has.no.line("[error]", true, 0)
        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.line(" {vault://mock/session-secret-unknown-again}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)

        assert(helpers.reload_kong("off", "reload --prefix " .. helpers.test_conf.prefix, {
          database = "off",
          vaults = "mocksocket",
          plugins = "session",
          declarative_config = "",
        }))

        assert.logfile().has.no.line("traceback", true, 0)
        assert.logfile().has.line(" {vault://mock/session-secret-unknown-again}", true, 0)
        assert.logfile().has.no.line("could not find vault", true, 0)

        proxy_client = helpers.proxy_client()

        local res = proxy_client:get("/")
        assert.res_status(404, res)
        local body = assert.response(res).has.jsonbody()
        assert.equal("no Route matched with those values", body.message)
      end)
    end
  end)

  describe("deprecated properties", function()
    it("deprecate <worker_consistency>", function()
      local _, stderr, _ = assert(kong_exec("start", {
        prefix = PREFIX,
        worker_consistency = "strict",
      }))
      assert.matches("the configuration value 'strict' for configuration property 'worker_consistency' is deprecated", stderr, nil, true)
      assert.matches("the 'worker_consistency' configuration property is deprecated", stderr, nil, true)
    end)
  end)

  describe("dangling socket cleanup", function()
    local pidfile = TEST_CONF.nginx_pid

    -- the worker events socket is just one of many unix sockets we use
    local event_sock = PREFIX .. "/worker_events.sock"

    local env = {
      prefix                      = PREFIX,
      database                    = strategy,
      admin_listen                = "127.0.0.1:9001",
      proxy_listen                = "127.0.0.1:8000",
      stream_listen               = "127.0.0.1:9022",
      nginx_main_worker_processes = 2, -- keeping this low for the sake of speed
    }

    local start_cmd = fmt("start -p %q -c %q", PREFIX, TEST_CONF_PATH)

    local function start()
      local ok, code, stdout, stderr = kong_exec(start_cmd, env, true)

      if ok then
        wait_until_healthy()
      end

      return ok, code, stdout, stderr
    end

    local function assert_start()
      local ok, code, stdout, stderr = start()
      assert(ok, "failed to start kong...\n"
              .. "exit code: " .. tostring(code) .. "\n"
              .. "stdout:\n" .. tostring(stdout) .. "\n"
              .. "stderr:\n" .. tostring(stderr) .. "\n")

      assert.equals(0, code)
      assert.matches("Kong started", stdout)

      return stdout, stderr
    end


    local function sigkill(pid)
      if type(pid) == "table" then
        pid = table.concat(pid, " ")
      end

      helpers.execute("kill -9 " .. pid)

      helpers.wait_until(function()
        -- kill returns:
        --
        -- * 0 on success
        -- * 1 on failure
        -- * 64 on partial failure/success
        --
        -- we might be passing in multiple pids, so we need to explicitly
        -- check the exit code is 1, otherwise one or more processes might
        -- still be alive
        local _, code = helpers.execute("kill -0 " .. pid, true)
        return code == 1
      end)
    end

    local function get_worker_pids()
      local admin = assert(helpers.admin_client())
      local res = admin:get("/")

      assert.res_status(200, res)

      local json = assert.response(res).has.jsonbody()
      admin:close()

      return json.pids.workers
    end

    local function kill_all()
      local workers = get_worker_pids()

      local master = assert(read_file(pidfile))
      master = master:gsub("%s+", "")
      sigkill(master)
      sigkill(workers)
    end


    before_each(function()
      helpers.clean_prefix(PREFIX)

      assert_start()

      kill_all()

      assert(helpers.path.exists(event_sock),
             "events socket (" .. event_sock .. ") unexpectedly removed")
    end)

    it("removes unix socket files in the prefix directory", function()
      local _, stderr = assert_start()

      assert.matches("[warn] Found dangling unix sockets in the prefix directory", stderr, nil, true)
      assert.matches(PREFIX, stderr, nil, true)

      assert.matches("removing unix socket", stderr)
      assert.matches(event_sock, stderr, nil, true)
    end)

    it("does not log anything if Kong was stopped cleanly and no sockets are found", function()
      assert_start()

      assert(helpers.stop_kong(PREFIX, true))

      local stdout, stderr = assert_start()

      assert.not_matches("prefix directory .*not found", stdout)
      assert.not_matches("[warn] Found dangling unix sockets in the prefix directory", stderr, nil, true)
      assert.not_matches("unix socket", stderr)
    end)

    it("does not do anything if kong is already running", function()
      assert_start()

      local ok, code, _, stderr = start()
      assert.falsy(ok, "expected `kong start` to fail with kong already running")
      assert.equals(1, code)
      assert.not_matches("unix socket", stderr)
      assert(helpers.path.exists(event_sock))
    end)
  end)

  describe("docker-start", function()
    -- tests here are meant to emulate the behavior of `kong docker-start`, which
    -- is a fake CLI command found in our default docker entrypoint:
    --
    -- https://github.com/Kong/docker-kong/blob/d588854aaeeab7ac39a0e801e9e6a1ded2f65963/docker-entrypoint.sh
    --
    -- this is the only(?) context where nginx is typically invoked directly
    -- instead of first going through `kong.cmd.start`, so it has some subtle
    -- differences

    it("works with resty.events when KONG_PREFIX is a relative path", function()
      local prefix = "relpath"

      finally(function()
        -- this test uses a non-default prefix, so it must manage
        -- its kong instance directly
        helpers.stop_kong(prefix)
      end)

      assert(kong_exec(fmt("prepare -p %q -c %q", prefix, TEST_CONF_PATH), {
        database = strategy,
        proxy_listen = "127.0.0.1:8000",
        stream_listen = "127.0.0.1:9000",
        admin_listen  = "127.0.0.1:8001",
      }))

      local nginx, err = require("kong.cmd.utils.nginx_signals").find_nginx_bin()
      assert.is_string(nginx, err)

      local started
      started, err = helpers.execute(fmt("%s -p %q -c nginx.conf",
                                    nginx, prefix))

      assert.truthy(started, "starting Kong failed: " .. tostring(err))

      -- wait until everything is running
      wait_until_healthy(prefix)

      assert.truthy(helpers.path.exists(prefix .. "/worker_events.sock"))
      assert.truthy(helpers.path.exists(prefix .. "/stream_worker_events.sock"))

      local log = prefix .. "/logs/error.log"
      assert.logfile(log).has.no.line("[error]", true, 0)
      assert.logfile(log).has.no.line("[alert]", true, 0)
      assert.logfile(log).has.no.line("[crit]",  true, 0)
      assert.logfile(log).has.no.line("[emerg]", true, 0)
    end)
  end)

end)
end
