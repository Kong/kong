local helpers = require "spec.helpers"



for _, strategy in helpers.each_strategy() do

describe("kong start/stop #" .. strategy, function()
  lazy_setup(function()
    helpers.get_db_utils(nil, {
      "routes",
      "services",
    }) -- runs migrations
    helpers.prepare_prefix()
  end)
  after_each(function()
    helpers.kill_all()
  end)
  lazy_teardown(function()
    helpers.clean_prefix()
  end)

  it("start help", function()
    local _, stderr = helpers.kong_exec "start --help"
    assert.not_equal("", stderr)
  end)
  it("stop help", function()
    local _, stderr = helpers.kong_exec "stop --help"
    assert.not_equal("", stderr)
  end)
  it("start/stop gracefully with default conf/prefix", function()
    assert(helpers.kong_exec("start", {
      prefix = helpers.test_conf.prefix,
      database = helpers.test_conf.database,
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace
    }))
    assert(helpers.kong_exec("stop", {
      prefix = helpers.test_conf.prefix,
    }))
  end)
  it("start/stop custom Kong conf/prefix", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path))
    assert(helpers.kong_exec("stop --prefix " .. helpers.test_conf.prefix))
  end)
  it("start/stop Kong with only stream listeners enabled", function()
    assert(helpers.kong_exec("start ", {
      prefix = helpers.test_conf.prefix,
      admin_listen = "off",
      proxy_listen = "off",
      stream_listen = "127.0.0.1:9022",
    }))
    assert(helpers.kong_exec("stop", {
      prefix = helpers.test_conf.prefix
    }))
  end)
  it("start dumps Kong config in prefix", function()
    assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path))
    assert.truthy(helpers.path.exists(helpers.test_conf.kong_env))
  end)

  if strategy == "cassandra" then
    it("start resolves cassandra contact points", function()
      assert(helpers.kong_exec("start", {
        prefix = helpers.test_conf.prefix,
        database = strategy,
        cassandra_contact_points = "localhost",
        cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
      }))
      assert(helpers.kong_exec("stop", {
        prefix = helpers.test_conf.prefix,
      }))
    end)
  end

  it("creates prefix directory if it doesn't exist", function()
    finally(function()
      helpers.kill_all("foobar")
      pcall(helpers.dir.rmtree, "foobar")
    end)

    assert.falsy(helpers.path.exists("foobar"))
    assert(helpers.kong_exec("start --prefix foobar", {
      pg_database = helpers.test_conf.pg_database,
      cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
    }))
    assert.truthy(helpers.path.exists("foobar"))
  end)

  describe("verbose args", function()
    it("accepts verbose --v", function()
      local _, _, stdout = assert(helpers.kong_exec("start --v --conf " .. helpers.test_conf_path))
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
    end)
    it("accepts debug --vv", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf " .. helpers.test_conf_path))
      assert.matches("[verbose] prefix in use: ", stdout, nil, true)
      assert.matches("[debug] prefix = ", stdout, nil, true)
      assert.matches("[debug] database = ", stdout, nil, true)
    end)
    it("prints ENV variables when detected #postgres", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf " .. helpers.test_conf_path, {
        database = "postgres",
        admin_listen = "127.0.0.1:8001"
      }))
      assert.matches('KONG_DATABASE ENV found with "postgres"', stdout, nil, true)
      assert.matches('KONG_ADMIN_LISTEN ENV found with "127.0.0.1:8001"', stdout, nil, true)
    end)
    it("prints config in alphabetical order", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf " .. helpers.test_conf_path))
      assert.matches("admin_listen.*anonymous_reports.*cassandra_ssl.*prefix.*", stdout)
    end)
    it("does not print sensitive settings in config", function()
      local _, _, stdout = assert(helpers.kong_exec("start --vv --conf " .. helpers.test_conf_path, {
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
      assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path .. " --nginx-conf " .. templ_fixture))
      assert.truthy(helpers.path.exists(helpers.test_conf.nginx_conf))

      local contents = helpers.file.read(helpers.test_conf.nginx_conf)
      assert.matches("# This is a custom nginx configuration template for Kong specs", contents, nil, true)
      assert.matches("daemon on;", contents, nil, true)
    end)
  end)

  describe("/etc/hosts resolving in CLI", function()
    it("resolves #cassandra hostname", function()
      assert(helpers.kong_exec("start --vv --run-migrations --conf " .. helpers.test_conf_path, {
        cassandra_contact_points = "localhost",
        database = "cassandra"
      }))
    end)
    it("resolves #postgres hostname", function()
      assert(helpers.kong_exec("start --conf " .. helpers.test_conf_path, {
        pg_host = "localhost",
        database = "postgres"
      }))
    end)
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
        local ok, stderr  = helpers.kong_exec("start --conf "..helpers.test_conf_path)
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

        local ok, stderr  = helpers.kong_exec("start --conf "..helpers.test_conf_path)
        assert.False(ok)
        assert.matches("the current database schema does not match this version of Kong.", stderr)
      end)
      it("connection check errors are prefixed with DB-specific prefix", function()
        local ok, stderr = helpers.kong_exec("start --conf " .. helpers.test_conf_path, {
          pg_port = 99999,
          cassandra_port = 99999,
        })
        assert.False(ok)
        assert.matches("[" .. helpers.test_conf.database .. " error]", stderr, 1, true)
      end)
    end)
  end)

  describe("nginx_daemon = off", function()
    it("redirects nginx's stdout to 'kong start' stdout", function()
      local pl_utils = require "pl.utils"
      local pl_file = require "pl.file"

      local stdout_path = os.tmpname()

      finally(function()
        os.remove(stdout_path)
      end)

      local cmd = string.format("KONG_PROXY_ACCESS_LOG=/dev/stdout "    ..
                                "KONG_NGINX_DAEMON=off %s start -c %s " ..
                                ">%s 2>/dev/null &", helpers.bin_path,
                                helpers.test_conf_path, stdout_path)

      local ok, _, _, stderr = pl_utils.executeex(cmd)
      if not ok then
        error(stderr)
      end

      do
        local proxy_client

        -- get a connection, retry until kong starts
        helpers.wait_until(function()
          local pok
          pok, proxy_client = pcall(helpers.proxy_client)
          return pok
        end, 10)

        local res = assert(proxy_client:send {
          method = "GET",
          path = "/hello",
        })
        assert.res_status(404, res) -- no Route configured
      end

      assert(helpers.stop_kong(helpers.test_conf.prefix))

      -- TEST: since nginx started in the foreground, the 'kong start' command
      -- stdout should receive all of nginx's stdout as well.
      local stdout = pl_file.read(stdout_path)
      assert.matches([["GET /hello HTTP/1.1" 404]] , stdout, nil, true)
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
          helpers.stop_kong(helpers.test_conf.prefix)
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
    end)
  end

  describe("errors", function()
    it("start inexistent Kong conf file", function()
      local ok, stderr = helpers.kong_exec "start --conf foobar.conf"
      assert.False(ok)
      assert.is_string(stderr)
      assert.matches("Error: no file at: foobar.conf", stderr, nil, true)
    end)
    it("stop inexistent prefix", function()
      assert(helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database,
        cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
      }))

      local ok, stderr = helpers.kong_exec("stop --prefix inexistent")
      assert.False(ok)
      assert.matches("Error: no such prefix: .*/inexistent", stderr)
    end)
    it("notifies when Kong is already running", function()
      assert(helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database,
        cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
      }))

      local ok, stderr = helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database
      })
      assert.False(ok)
      assert.matches("Kong is already running in " .. helpers.test_conf.prefix, stderr, nil, true)
    end)
    it("should not stop Kong if already running in prefix", function()
      local kill = require "kong.cmd.utils.kill"

      assert(helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database,
        cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
      }))

      local ok, stderr = helpers.kong_exec("start --prefix " .. helpers.test_conf.prefix, {
        pg_database = helpers.test_conf.pg_database
      })
      assert.False(ok)
      assert.matches("Kong is already running in " .. helpers.test_conf.prefix, stderr, nil, true)

      assert(kill.is_running(helpers.test_conf.nginx_pid))
    end)
    it("ensures the required shared dictionaries are defined", function()
      local constants = require "kong.constants"
      local pl_file   = require "pl.file"
      local fmt       = string.format

      local templ_fixture     = "spec/fixtures/custom_nginx.template"
      local new_templ_fixture = "spec/fixtures/custom_nginx.template.tmp"

      finally(function()
        pl_file.delete(new_templ_fixture)
        helpers.stop_kong()
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
    it("ensures lua-resty-core is loaded", function()
        finally(function()
          helpers.stop_kong()
        end)

        local ok, err = helpers.start_kong({
          prefix = helpers.test_conf.prefix,
          database = helpers.test_conf.database,
          pg_database = helpers.test_conf.pg_database,
          cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
          nginx_http_lua_load_resty_core = "off",
        })
        assert.falsy(ok)
        assert.matches(helpers.unindent([[
          lua-resty-core must be loaded; make sure 'lua_load_resty_core'
          is not disabled.
        ]], nil, true), err, nil, true)
    end)

    if strategy == "cassandra" then
      it("errors when cassandra contact points cannot be resolved", function()
        local ok, stderr = helpers.start_kong({
          database = strategy,
          cassandra_contact_points = "invalid.inexistent.host",
          cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
        })

        assert.False(ok)
        assert.matches("could not resolve any of the provided Cassandra contact points " ..
                       "(cassandra_contact_points = 'invalid.inexistent.host')", stderr, nil, true)

        finally(function()
          helpers.stop_kong()
          helpers.kill_all()
          pcall(helpers.dir.rmtree)
        end)
      end)
    end

    if strategy == "off" then
      it("does not start with an invalid declarative config file", function()
        local yaml_file = helpers.make_yaml_file [[
          _format_version: "1.1"
          services:
          - name: "@gobo"
            url: http://mockbin.org
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
          helpers.stop_kong()
        end)

        local ok, err = helpers.start_kong({
          database = "off",
          declarative_config = yaml_file,
        })
        assert.falsy(ok)
        assert.matches(helpers.unindent[[
          in 'services':
            - in entry 1 of 'services':
              in 'name': invalid value '@gobo': it must only contain alphanumeric and '., -, _, ~' characters
            - in entry 2 of 'services':
              in 'routes':
                - in entry 1 of 'routes':
                  in 'hosts':
                    - in entry 2 of 'hosts': invalid hostname: \\99
        ]], err, nil, true)
      end)
    end

  end)

  describe("deprecated properties", function()
    describe("prints a warning to stderr", function()
      local u = helpers.unindent

      it("'upstream_keepalive'", function()
        local opts = {
          prefix = helpers.test_conf.prefix,
          database = helpers.test_conf.database,
          pg_database = helpers.test_conf.pg_database,
          cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
          upstream_keepalive = 0,
        }

        local _, stderr, stdout = assert(helpers.kong_exec("start", opts))
        assert.matches("Kong started", stdout, nil, true)
        assert.matches(u([[
          [warn] the 'upstream_keepalive' configuration property is deprecated,
          use 'nginx_http_upstream_keepalive' instead
        ]], nil, true), stderr, nil, true)

        local _, stderr, stdout = assert(helpers.kong_exec("stop", opts))
        assert.matches("Kong stopped", stdout, nil, true)
        assert.equal("", stderr)
      end)

      it("'service_mesh'", function()
        local opts = {
          prefix = helpers.test_conf.prefix,
          database = helpers.test_conf.database,
          pg_database = helpers.test_conf.pg_database,
          cassandra_keyspace = helpers.test_conf.cassandra_keyspace,
          service_mesh = "on",
        }

        local _, stderr, stdout = assert(helpers.kong_exec("start", opts))
        assert.matches("Kong started", stdout, nil, true)
        print(stderr)
        assert.matches("You enabled the deprecated Service Mesh feature of " ..
                       "the Kong Gateway, which will cause upstream HTTPS request " ..
                       "to behave incorrectly. Service Mesh support" ..
                       "in Kong Gateway will be removed in the next release."
        , stderr, nil, true)

        local _, stderr, stdout = assert(helpers.kong_exec("stop", opts))
        assert.matches("Kong stopped", stdout, nil, true)
        assert.equal("", stderr)
      end)
    end)
  end)
end)

end
