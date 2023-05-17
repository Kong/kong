local helpers   = require "spec.helpers"
local constants = require "kong.constants"

local cjson = require "cjson"

local fmt = string.format
local kong_exec = helpers.kong_exec
local read_file = helpers.file.read


local PREFIX = helpers.test_conf.prefix
local TEST_CONF = helpers.test_conf
local TEST_CONF_PATH = helpers.test_conf_path


for _, strategy in helpers.each_strategy() do

describe("kong start/stop #" .. strategy, function()
  lazy_setup(function()
    helpers.get_db_utils(strategy) -- runs migrations
    helpers.prepare_prefix()
  end)

  after_each(function()
    helpers.kill_all()
    helpers.clean_logfile()
  end)

  lazy_teardown(function()
    helpers.stop_kong()
    helpers.clean_prefix()
  end)

  it("fails with referenced values that are not initialized", function()
    local ok, stderr, stdout = kong_exec("start", {
      prefix = PREFIX,
      database = strategy,
      nginx_proxy_real_ip_header = "{vault://env/ipheader}",
      pg_database = TEST_CONF.pg_database,
      cassandra_keyspace = TEST_CONF.cassandra_keyspace,
      vaults = "env",
    })

    assert.matches("Error: failed to dereference '{vault://env/ipheader}': unable to load value (ipheader) from vault (env): not found [{vault://env/ipheader}] for config option 'nginx_proxy_real_ip_header'", stderr, nil, true)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("fails to read referenced secrets when vault does not exist", function()
    local ok, stderr, stdout = kong_exec("start", {
      prefix = PREFIX,
      database = TEST_CONF.database,
      pg_password = "{vault://non-existent/pg_password}",
      pg_database = TEST_CONF.pg_database,
      cassandra_keyspace = TEST_CONF.cassandra_keyspace,
    })

    assert.matches("failed to dereference '{vault://non-existent/pg_password}': vault not found (non-existent)", stderr, nil, true)
    assert.is_nil(stdout)
    assert.is_false(ok)
  end)

  it("resolves referenced secrets", function()
    helpers.setenv("PG_PASSWORD", "dummy")

    local _, stderr, stdout = assert(kong_exec("start", {
      prefix = PREFIX,
      database = TEST_CONF.database,
      pg_password = "{vault://env/pg_password}",
      pg_database = TEST_CONF.pg_database,
      cassandra_keyspace = TEST_CONF.cassandra_keyspace,
      vaults = "env",
    }))

    assert.not_matches("failed to dereference {vault://env/pg_password}", stderr, nil, true)
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
      cassandra_keyspace = TEST_CONF.cassandra_keyspace
    }))

    assert(kong_exec("stop", { prefix = PREFIX }))
  end)

  it("start/stop stops without error when references cannot be resolved #test", function()
    helpers.setenv("PG_PASSWORD", "dummy")

    local _, stderr, stdout = assert(kong_exec("start", {
      prefix = PREFIX,
      database = TEST_CONF.database,
      pg_password = "{vault://env/pg_password}",
      pg_database = TEST_CONF.pg_database,
      cassandra_keyspace = TEST_CONF.cassandra_keyspace,
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

    assert(kong_exec("stop", { prefix = PREFIX }))
  end)

  it("start dumps Kong config in prefix", function()
    assert(kong_exec("start --conf " .. TEST_CONF_PATH))
    assert.truthy(helpers.path.exists(TEST_CONF.kong_env))
  end)

  if strategy == "cassandra" then
    it("should not add [emerg], [alert], [crit], or [error] lines to error log", function()
      assert(kong_exec("start ", {
        prefix = PREFIX,
        stream_listen = "127.0.0.1:9022",
        status_listen = "0.0.0.0:8100",
      }))

      assert(kong_exec("stop", {
        prefix = PREFIX
      }))

      assert.logfile().has.no.line("[emerg]", true)
      assert.logfile().has.no.line("[alert]", true)
      assert.logfile().has.no.line("[crit]", true)
      assert.logfile().has.no.line("[error]", true)
    end)

  else
    it("should not add [emerg], [alert], [crit], [error] or [warn] lines to error log", function()
      assert(kong_exec("start ", {
        prefix = PREFIX,
        stream_listen = "127.0.0.1:9022",
        status_listen = "0.0.0.0:8100",
      }))

      ngx.sleep(0.1)   -- wait unix domain socket
      assert(kong_exec("stop", { prefix = PREFIX }))

      assert.logfile().has.no.line("[emerg]", true)
      assert.logfile().has.no.line("[alert]", true)
      assert.logfile().has.no.line("[crit]", true)
      assert.logfile().has.no.line("[error]", true)
      assert.logfile().has.no.line("[warn]", true)
    end)
  end

  if strategy == "cassandra" then
    it("start resolves cassandra contact points", function()
      assert(kong_exec("start", {
        prefix = PREFIX,
        database = strategy,
        cassandra_contact_points = "localhost",
        cassandra_keyspace = TEST_CONF.cassandra_keyspace,
      }))

      assert(kong_exec("stop", { prefix = PREFIX }))
    end)
  end

  it("creates prefix directory if it doesn't exist", function()
    finally(function()
      helpers.kill_all("foobar")
      pcall(helpers.dir.rmtree, "foobar")
    end)

    assert.falsy(helpers.path.exists("foobar"))
    assert(kong_exec("start --prefix foobar", {
      pg_database = TEST_CONF.pg_database,
      cassandra_keyspace = TEST_CONF.cassandra_keyspace,
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
      local _, _, stdout = assert(kong_exec("start --vv --conf " .. TEST_CONF_PATH))
      assert.matches("admin_listen.*anonymous_reports.*cassandra_ssl.*prefix.*", stdout)
    end)

    it("does not print sensitive settings in config", function()
      local _, _, stdout = assert(kong_exec("start --vv --conf " .. TEST_CONF_PATH, {
        pg_password = "do not print",
        cassandra_password = "do not print",
      }))
      assert.matches('KONG_PG_PASSWORD ENV found with "******"', stdout, nil, true)
      assert.matches('KONG_CASSANDRA_PASSWORD ENV found with "******"', stdout, nil, true)
      assert.matches('pg_password = "******"', stdout, nil, true)
      assert.matches('cassandra_password = "******"', stdout, nil, true)
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
    if strategy == "cassandra" then
      it("resolves #cassandra hostname", function()
        assert(kong_exec("start --vv --run-migrations --conf " .. TEST_CONF_PATH, {
          cassandra_contact_points = "localhost",
          database = "cassandra"
        }))
      end)

    elseif strategy == "postgres" then
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
          cassandra_port = 99999,
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
      if not ok then
        error(stderr)
      end

      helpers.wait_until(function()
        local cmd = fmt("%s health -p ./servroot", helpers.bin_path)
        return helpers.execute(cmd, true)
      end, 10)

      local proxy_client = assert(helpers.proxy_client())

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/hello",
      })
      assert.res_status(404, res) -- no Route configured
      assert(helpers.stop_kong(PREFIX))

      -- TEST: since nginx started in the foreground, the 'kong start' command
      -- stdout should receive all of nginx's stdout as well.
      local stdout = read_file(stdout_path)
      assert.matches([["GET /hello HTTP/1.1" 404]] , stdout, nil, true)
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
      if not ok then
        error(stderr)
      end

      helpers.wait_until(function()
        local cmd = fmt("%s health -p ./servroot", helpers.bin_path)
        return helpers.execute(cmd, true)
      end, 10)

      local proxy_client = assert(helpers.proxy_client())

      local res = assert(proxy_client:send {
        method = "GET",
        path = "/hello",
      })
      assert.res_status(404, res) -- no Route configured

      helpers.pwait_until(function()
        -- TEST: since nginx started in the foreground, the 'kong start' command
        -- stdout should receive all of nginx's stdout as well.
        local stdout = read_file(stdout_path)
        assert.matches([["GET /hello HTTP/1.1" 404]] , stdout, nil, true)
      end, 10)

      assert(kong_exec("quit --prefix " .. PREFIX))
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

        local proxy_client

        finally(function()
          os.remove(yaml_file)
          if proxy_client then
            proxy_client:close()
          end
        end)

        assert(helpers.start_kong({
          database = "off",
          declarative_config = yaml_file,
          nginx_worker_processes = 100, -- stress test initialization
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        helpers.wait_until(function()
          -- get a connection, retry until kong starts
          helpers.wait_until(function()
            local pok
            pok, proxy_client = pcall(helpers.proxy_client)
            return pok
          end, 10)

          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
            headers = {
              host = "example.test",
            }
          })
          local ok = res.status == 200

          if proxy_client then
            proxy_client:close()
            proxy_client = nil
          end

          return ok
        end, 10)
      end)

      it("starts with a valid declarative config string", function()
        local config_string = [[{"_format_version":"1.1","services":[{"name":"my-service","url":"http://127.0.0.1:15555","routes":[{"name":"example-route","hosts":["example.test"]}]}]}]]
        local proxy_client

        finally(function()
          if proxy_client then
            proxy_client:close()
          end
        end)

        assert(helpers.start_kong({
          database = "off",
          declarative_config_string = config_string,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        helpers.wait_until(function()
          -- get a connection, retry until kong starts
          helpers.wait_until(function()
            local pok
            pok, proxy_client = pcall(helpers.proxy_client)
            return pok
          end, 10)

          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
            headers = {
              host = "example.test",
            }
          })
          local ok = res.status == 200

          if proxy_client then
            proxy_client:close()
            proxy_client = nil
          end

          return ok
        end, 10)
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

        local admin_client, json_body

        finally(function()
          os.remove(yaml_file)
          if admin_client then
            admin_client:close()
          end
        end)

        assert(helpers.start_kong({
          database = "off",
          declarative_config = yaml_file,
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        helpers.wait_until(function()
          helpers.wait_until(function()
            local pok
            pok, admin_client = pcall(helpers.admin_client)
            return pok
          end, 10)

          local res = assert(admin_client:send {
            method = "GET",
            path = "/status"
          })
          if res.status ~= 200 then
            return false
          end
          local body = assert.res_status(200, res)
          json_body = cjson.decode(body)

          if admin_client then
            admin_client:close()
            admin_client = nil
          end

          return true
        end, 10)

        assert.is_string(json_body.configuration_hash)
        assert.equals(32, #json_body.configuration_hash)
        assert.not_equal(constants.DECLARATIVE_EMPTY_CONFIG_HASH, json_body.configuration_hash)
      end)

      it("hash is set correctly for an empty configuration", function()

        local admin_client, json_body

        finally(function()
          if admin_client then
            admin_client:close()
          end
        end)

        -- not specifying declarative_config this time
        assert(helpers.start_kong({
          database = "off",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }))

        helpers.wait_until(function()
          helpers.wait_until(function()
            local pok
            pok, admin_client = pcall(helpers.admin_client)
            return pok
          end, 10)

          local res = assert(admin_client:send {
            method = "GET",
            path = "/status"
          })
          if res.status ~= 200 then
            return false
          end
          local body = assert.res_status(200, res)
          json_body = cjson.decode(body)

          if admin_client then
            admin_client:close()
            admin_client = nil
          end

          return true
        end, 10)

        assert.is_string(json_body.configuration_hash)
        assert.equals(constants.DECLARATIVE_EMPTY_CONFIG_HASH, json_body.configuration_hash)
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
      assert(kong_exec("start --prefix " .. PREFIX, {
        pg_database = TEST_CONF.pg_database,
        cassandra_keyspace = TEST_CONF.cassandra_keyspace,
      }))

      local ok, stderr = kong_exec("stop --prefix inexistent")
      assert.False(ok)
      assert.matches("Error: no such prefix: .*/inexistent", stderr)
    end)

    it("notifies when Kong is already running", function()
      assert(kong_exec("start --prefix " .. PREFIX, {
        pg_database = TEST_CONF.pg_database,
        cassandra_keyspace = TEST_CONF.cassandra_keyspace,
      }))

      local ok, stderr = kong_exec("start --prefix " .. PREFIX, {
        pg_database = TEST_CONF.pg_database
      })
      assert.False(ok)
      assert.matches("Kong is already running in " .. PREFIX, stderr, nil, true)
    end)

    it("should not start Kong if already running in prefix", function()
      local kill = require "kong.cmd.utils.kill"

      assert(kong_exec("start --prefix " .. PREFIX, {
        pg_database = TEST_CONF.pg_database,
        cassandra_keyspace = TEST_CONF.cassandra_keyspace,
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
      local templ_fixture     = "spec/fixtures/custom_nginx.template"
      local new_templ_fixture = "spec/fixtures/custom_nginx.template.tmp"

      finally(function()
        os.remove(new_templ_fixture)
      end)

      for _, dict in ipairs(constants.DICTS) do
        -- remove shared dictionary entry
        assert(os.execute(fmt("sed '/lua_shared_dict %s .*;/d' %s > %s",
                              dict, templ_fixture, new_templ_fixture)))

        local ok, err = helpers.start_kong({ nginx_conf = new_templ_fixture })
        assert.falsy(ok)
        assert.matches(
          "missing shared dict '" .. dict .. "' in Nginx configuration, "    ..
          "are you using a custom template? Make sure the 'lua_shared_dict " ..
          dict .. " [SIZE];' directive is defined.", err, nil, true)
      end
    end)

    if strategy == "cassandra" then
      it("errors when cassandra contact points cannot be resolved", function()
        local ok, stderr = helpers.start_kong({
          database = strategy,
          cassandra_contact_points = "invalid.inexistent.host",
          cassandra_keyspace = TEST_CONF.cassandra_keyspace,
        })

        assert.False(ok)
        assert.matches("could not resolve any of the provided Cassandra contact points " ..
                       "(cassandra_contact_points = 'invalid.inexistent.host')", stderr, nil, true)
      end)
    end

    if strategy == "off" then
      it("does not start with an invalid declarative config file", function()
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

    local function start()
      local cmd = fmt("start -p %q", PREFIX)
      return kong_exec(cmd, env, true)
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

      assert(start())

      -- sanity
      helpers.wait_until(function()
        return kong_exec("health", env)
      end, 5)

      -- sanity
      helpers.wait_until(function()
        return helpers.path.exists(event_sock)
      end, 5)

      kill_all()

      assert(helpers.path.exists(event_sock),
             "events socket (" .. event_sock .. ") unexpectedly removed")
    end)

    it("removes unix socket files in the prefix directory", function()
      local ok, code, stdout, stderr = start()
      assert.truthy(ok, "expected `kong start` to succeed: " .. tostring(code or stderr))
      assert.equals(0, code)

      assert.matches("Kong started", stdout)

      assert.matches("[warn] Found dangling unix sockets in the prefix directory", stderr, nil, true)
      assert.matches(PREFIX, stderr, nil, true)

      assert.matches("removing unix socket", stderr)
      assert.matches(event_sock, stderr, nil, true)
    end)

    it("does not log anything if Kong was stopped cleanly and no sockets are found", function()
      local ok, code, stdout, stderr = start()
      assert.truthy(ok, "expected `kong start` to succeed: " .. tostring(code or stderr))
      assert.equals(0, code)
      assert.matches("Kong started", stdout)

      assert(helpers.stop_kong(PREFIX, true))

      ok, code, stdout, stderr = start()

      assert.truthy(ok, "expected `kong start` to succeed: " .. tostring(code or stderr))
      assert.equals(0, code)
      assert.matches("Kong started", stdout)
      assert.not_matches("prefix directory .*not found", stdout)

      assert.not_matches("[warn] Found dangling unix sockets in the prefix directory", stderr, nil, true)
      assert.not_matches("unix socket", stderr)
    end)

    it("does not do anything if kong is already running", function()
      local ok, code, stdout, stderr = start()
      assert.truthy(ok, "initial startup of kong failed: " .. stderr)
      assert.equals(0, code)

      assert.matches("Kong started", stdout)

      ok, code, _, stderr = start()
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
        helpers.kill_all(prefix)
        pcall(helpers.dir.rmtree, prefix)
      end)

      assert(kong_exec(fmt("prepare -p %q", prefix), {
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
      helpers.wait_until(function()
        local client = helpers.admin_client(5000, 8001)
        local res, rerr = client:send({
          method = "GET",
          path = "/",
        })

        if res then res:read_body() end
        client:close()

        assert.is_table(res, rerr)

        return res.status == 200
      end)

      assert.truthy(helpers.path.exists(prefix .. "/worker_events.sock"))
      assert.truthy(helpers.path.exists(prefix .. "/stream_worker_events.sock"))

      assert.logfile(prefix .. "/logs/error.log").has.no.line("[error]", true)
      assert.logfile(prefix .. "/logs/error.log").has.no.line("[alert]", true)
      assert.logfile(prefix .. "/logs/error.log").has.no.line("[crit]", true)
      assert.logfile(prefix .. "/logs/error.log").has.no.line("[emerg]", true)
    end)
  end)

end)
end
