-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local DB = require "kong.db.init"
local tb_clone = require "table.clone"
local shell = require "resty.shell"


-- Current number of migrations to execute in a new install
-- additional 2 for EE
local nr_migrations = 1 + 2 -- 11


local lua_path = [[ KONG_LUA_PATH_OVERRIDE="./spec/fixtures/migrations/?.lua;]] ..
                 [[./spec/fixtures/migrations/?/init.lua;]]..
                 [[./spec/fixtures/custom_plugins/?.lua;]]..
                 [[./spec/fixtures/custom_plugins/?/init.lua;" ]]


for _, strategy in helpers.each_strategy() do


  local function run_kong(cmd, env, no_lua_path_overrides)
    env = env or {}
    env.database = strategy
    env.plugins = env.plugins or "off"
    -- note: run migration command tests in a separate schema
    -- so it won't affect default schema's ACL which are specially
    -- set for readonly mode tests later
    env.pg_schema = "kong_migrations_tests"

    local lpath
    if not no_lua_path_overrides then
      lpath = lua_path
    end

    local cmdline = cmd .. " -c " .. helpers.test_conf_path
    local _, code, stdout, stderr = helpers.kong_exec(cmdline, env, true, lpath)
    return code, stdout, stderr
  end


  local function init_db()
    local tmp_conf = tb_clone(helpers.test_conf)
    tmp_conf.pg_schema = "kong_migrations_tests"

    local db = assert(DB.new(tmp_conf, strategy))
    assert(db:init_connector())
    -- in spec/helpers.lua, db has already been init'ed
    -- the stored connection will be reused here,
    -- so we need to set schema explicitly to 'kong_migrations_tests'
    assert(db:connect())
    assert(db.connector:query("SET SCHEMA 'kong_migrations_tests';\n"))
    finally(function()
      db.connector:close()
    end)
    return db
  end


  describe("kong migrations #" .. strategy, function()

    lazy_teardown(function()
      run_kong("migrations reset --yes")
    end)

    it("rejects invalid commands", function()
      local code, _, stderr = run_kong("migrations invalid")
      assert.same(1, code)
      assert.match("No such command for migrations: invalid", stderr, 1, true)
    end)

    describe("#db reset", function()
      it("cannot run non-interactively without --yes", function()
        local cmd = string.format(helpers.unindent [[
          echo y | %s KONG_DATABASE=%s %s migrations reset --v -c %s
        ]], lua_path, strategy, helpers.bin_path, helpers.test_conf_path)
        local ok, _, stderr, _, code = shell.run(cmd, nil, 0)
        assert.falsy(ok)
        assert.same(1, code)
        assert.match("not a tty", stderr, 1, true)
      end)

      it("runs non-interactively with --yes", function()
        run_kong("migrations bootstrap")
        local db = init_db()
        local code = run_kong("migrations reset --yes")
        assert.same(0, code)

        -- schema_migrations returns nil when it is reset
        local migrations, err = db.connector:schema_migrations()
        assert.is_nil(migrations)
        assert.is_nil(err)
      end)

      it("runs even if database is in a bad state", function()
        run_kong("migrations bootstrap")
        local db = init_db()

        -- valid SQL and CQL
        db.connector:query("DROP TABLE locks;")

        local code = run_kong("migrations reset --yes")
        assert.same(0, code)

        -- schema_migrations returns nil when it is reset
        local migrations, err = db.connector:schema_migrations()
        assert.is_nil(migrations)
        assert.is_nil(err)
      end)

      it("does not reset twice", function()
        run_kong("migrations reset --yes")
        local code, stdout = run_kong("migrations reset --yes")
        assert.same(1, code)
        assert.match("nothing to reset", stdout, 1, true)
      end)
    end)

    describe("bootstrap", function()
      it("#db runs and bootstraps the database", function()
        run_kong("migrations reset --yes")
        local code, stdout = run_kong("migrations bootstrap")
        assert.same(0, code)
        assert.match("\nmigrating core", stdout, 1, true)
        assert.match("\n" .. nr_migrations .. " migration", stdout, 1, true)
        assert.match("\nDatabase is up-to-date\n", stdout, 1, true)
      end)

      it("#db migration bootstraps can reinitialize the workspace entity counters automatically", function()
        run_kong("migrations reset --yes")
        local code = run_kong("migrations bootstrap")
        assert.same(0, code)

        local db = init_db()
        local rows = db.connector:query([[SELECT count(*) FROM workspace_entity_counters;]])
        assert.same(1, rows[1].count)
      end)

      if strategy == "off" then
        it("always reports as bootstrapped", function()
          local code, stdout = run_kong("migrations bootstrap")
          assert.same(0, code)
          assert.match("Database already bootstrapped", stdout, 1, true)
        end)
      end

      it("does not bootstrap twice", function()
        local code = run_kong("migrations bootstrap")
        assert.same(0, code)
        local stdout
        code, stdout = run_kong("migrations bootstrap")
        assert.same(0, code)
        assert.match("Database already bootstrapped", stdout, 1, true)
      end)

      it("#db does bootstrap twice if forced", function()
        local code = run_kong("migrations bootstrap")
        assert.same(0, code)
        local stdout
        code, stdout = run_kong("migrations bootstrap --force")
        assert.same(0, code)
        assert.match("\nmigrating core", stdout, 1, true)
        assert.match("\n" .. nr_migrations .. " migration", stdout, 1, true)
        assert.match("\nDatabase is up-to-date\n", stdout, 1, true)
      end)

      pending("-q suppresses all output", function()
        local code, stdout, stderr = run_kong("migrations bootstrap -q")
        assert.same(0, code)
        assert.same(0, #stdout)
        assert.same(0, #stderr)
      end)

      it("-p accepts a prefix override", function()
        local code, stdout, stderr = run_kong("migrations bootstrap -p /dev/null")
        assert.equal(1, code)
        assert.equal(0, #stdout)
        assert.match("/dev/null is not a directory", stderr, 1, true)
      end)
    end)

    describe("list", function()
      it("#db fails if not bootstrapped", function()
        local code = run_kong("migrations reset --yes")
        assert.same(0, code)
        local stdout
        code, stdout = run_kong("migrations list")
        assert.same(3, code)
        assert.match("Database needs bootstrapping or is older than Kong 1.0", stdout, 1, true)
      end)

      it("lists migrations if bootstrapped", function()
        local code = run_kong("migrations bootstrap")
        assert.same(0, code)
        code = run_kong("migrations up")
        assert.same(0, code)
        local stdout
        code, stdout = run_kong("migrations list")
        assert.same(0, code)
        assert.match("Executed migrations:", stdout, 1, true)

        if strategy ~= "off" then
          -- to avoid postgresql error:
          -- [PostgreSQL error] failed to retrieve PostgreSQL server_version_num: receive_message:
          -- failed to get type: timeout
          -- when testing on ARM64 platform which has low single-core performance

          local pok, db
          helpers.wait_until(function()
            pok, db = pcall(init_db)
            return pok
          end, 10)

          -- valid CQL and SQL; don't expect to go over one page in CQL here
          local rows = db.connector:query([[SELECT * FROM schema_meta;]])
          local n = 0
          for _, row in ipairs(rows) do
            n = n + #row.executed
          end
          assert.same(nr_migrations, n)
        end
      end)

      it("#db lists pending migrations if any", function()
        run_kong("migrations bootstrap")
        local code, stdout = run_kong("migrations list", {
          plugins = "with-migrations",
        })
        assert.same(5, code)
        -- assert.match("database has new migrations available:\n" ..
        --              "session: 000_base_session\n" ..
        --              "with-migrations: 000_base_with_migrations, 001_14_to_15",
        assert.match("Executed migrations:\n" ..
                     "      core: 000_base\n" ..
                     "enterprise: 000_base, 006_1301_to_1500\n\n" ..
                     "New migrations available:\n" ..
                     "        session: 000_base_session, 001_add_ttl_index, 002_320_to_330\n" ..
                     "with-migrations: 000_base_with_migrations, 001_14_to_15\n\n" ..
                     "Run 'kong migrations up' to proceed",
                     stdout, 1, true)
      end)

      pending("-q suppresses all output", function()
        local code, stdout, stderr = run_kong("migrations list -q")
        assert.same(0, code)
        assert.same(0, #stdout)
        assert.same(0, #stderr)
      end)
    end)

    describe("up", function()
      it("#db performs first phase of migration", function()
        run_kong("migrations reset --yes")
        local code = run_kong("migrations bootstrap")
        assert.same(0, code)

        local stdout, stderr
        code, stdout, stderr = run_kong("migrations up", {
          plugins = "with-migrations",
        })
        assert.match("5 migrations processed", stdout .. "\n" .. stderr, 1, true)
        assert.match("4 executed", stdout .. "\n" .. stderr, 1, true)
        assert.match("1 pending", stdout .. "\n" .. stderr, 1, true)
        assert.same(0, code)

        code, stdout = run_kong("migrations up")
        assert.same(0, code)
        assert.match("Database is already up-to-date", stdout, 1, true)

        local db = init_db()
        -- valid CQL and SQL; don't expect to go over one page in CQL here
        local rows = db.connector:query([[SELECT * FROM schema_meta;]])
        local executed = 0
        local pending = 0
        for _, row in ipairs(rows) do
          executed = executed + #row.executed
          pending = pending + (type(row.pending) == "table" and #row.pending or 0)
        end

        assert.same(nr_migrations + 4, executed)
        assert.same(1, pending)
      end)

      it("#db non-proxy consumers should not count in workspace entity counters", function()
        run_kong("migrations reset --yes")

        local env_mock_admin_consumer = "KONG_TEST_MOCK_ADMIN_CONSUMER"
        if not os.getenv(env_mock_admin_consumer) then
          finally(function() helpers.unsetenv(env_mock_admin_consumer) end)
          helpers.setenv(env_mock_admin_consumer, "true")
        end

        local code = run_kong("migrations bootstrap")
        assert.same(0, code)

        local db = init_db()
        local rows = db.connector:query([[SELECT count(*) FROM consumers;]])
        assert.same(1, rows[1].count)

        rows = db.connector:query([[
          SELECT count(*) FROM workspace_entity_counters WHERE entity_type = 'consumers';
        ]])
        assert.same(0, rows[1].count)

        code = run_kong("migrations up", {
          plugins = "with-migrations",
        })
        assert.same(0, code)

        rows = db.connector:query([[
          SELECT count(*) FROM workspace_entity_counters WHERE entity_type = 'consumers';
        ]])
        assert.same(0, rows[1].count)
      end)

      if strategy == "off" then
        it("always reports as up-to-date", function()
          local code, stdout = run_kong("migrations up")
          assert.same(0, code)
          assert.match("Database is already up-to-date", stdout, 1, true)
        end)
      end

      pending("-q suppresses all output", function()
        local code, stdout, stderr = run_kong("migrations up -q")
        assert.same(0, code)
        assert.same(0, #stdout)
        assert.same(0, #stderr)
      end)
    end)

    describe("finish", function()
      it("#db performs second phase of migration", function()
        run_kong("migrations reset --yes")
        run_kong("migrations bootstrap")

        local code = run_kong("migrations up", {
          plugins = "with-migrations",
        })
        assert.same(0, code)

        local stdout, stderr
        code, stdout, stderr = run_kong("migrations finish", {
          plugins = "with-migrations",
        })
        assert.match("1 migration processed", stdout .. "\n" .. stderr, 1, true)
        assert.match("1 executed", stdout .. "\n" .. stderr, 1, true)
        assert.same(0, code)

        code, stdout = run_kong("migrations finish")
        assert.same(0, code)
        assert.match("No pending migrations to finish", stdout, 1, true)

        local db = init_db()
        -- valid CQL and SQL; don't expect to go over one page in CQL here
        local rows = db.connector:query([[SELECT * FROM schema_meta;]])
        local executed = 0
        local pending = 0
        for _, row in ipairs(rows) do
          executed = executed + #row.executed
          pending = pending + (type(row.pending) == "table" and #row.pending or 0)
        end
        --assert.same({}, rows)
        assert.same(nr_migrations + 5, executed)
        assert.same(0, pending)
      end)

      it("#db migration finish can reinitialize the workspace entity counters automatically", function()
        run_kong("migrations reset --yes")
        run_kong("migrations bootstrap")

        local db = init_db()
        local rows = db.connector:query([[SELECT count(*) FROM workspace_entity_counters;]])
        assert.same(1, rows[1].count)

        local code = run_kong("migrations up", {
          plugins = "with-migrations",
        })
        assert.same(0, code)

        rows = db.connector:query([[SELECT count(*) FROM workspace_entity_counters;]])
        assert.same(1, rows[1].count)

        code = run_kong("migrations finish", {
          plugins = "with-migrations",
        })
        assert.same(0, code)

        rows = db.connector:query([[SELECT count(*) FROM workspace_entity_counters;]])
        assert.same(3, rows[1].count)
      end)

      if strategy == "off" then
        it("always reports as done", function()
          local code, stdout = run_kong("migrations finish")
          assert.same(0, code)
          assert.match("No pending migrations to finish", stdout, 1, true)
        end)
      end

      pending("-q suppresses all output", function()
        local code, stdout, stderr = run_kong("migrations finish -q")
        assert.same(0, code)
        assert.same(0, #stdout)
        assert.same(0, #stderr)
      end)
    end)

    describe("reentrancy " .. strategy, function()

      lazy_setup(function()
        run_kong("migrations reset --yes")
      end)

      after_each(function()
        run_kong("migrations reset --yes")
      end)

      it("#db is reentrant with migrations up -f", function()
        local _, code, stdout, stderr
        code, _, stderr = run_kong("migrations reset --yes", {
          plugins = "bundled"
        }, true)
        assert.equal(1, code)
        assert.equal("", stderr)

        code, _, stderr = run_kong("migrations bootstrap", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        assert.equal("", stderr)

        code, stdout, stderr = run_kong("migrations up", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        assert.equal("Database is already up-to-date", utils.strip(stdout))
        assert.equal("", stderr)

        code, stdout, stderr = run_kong("migrations up -f", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        assert.equal("", stderr)

        local code2, stdout2, stderr2 = run_kong("migrations up -f", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        assert.equal("", stderr)

        assert.equal(code, code2)
        assert.equal(stdout, stdout2)
        assert.equal(stderr, stderr2)
      end)

      it("#db is reentrant with migrations finish -f", function()
        local _, code, stdout, stderr
        code, _, stderr = run_kong("migrations reset --yes", {
          plugins = "bundled"
        }, true)
        assert.equal(1, code)
        assert.equal("", stderr)

        code, _, stderr = run_kong("migrations bootstrap", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        assert.equal("", stderr)

        code, stdout, stderr = run_kong("migrations up", {
          plugins = "bundled"
        }, true)

        assert.equal(0, code)
        assert.equal("Database is already up-to-date", utils.strip(stdout))
        assert.equal("", stderr)

        code, stdout, stderr = run_kong("migrations finish", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        assert.equal("No pending migrations to finish", utils.strip(stdout))
        assert.equal("", stderr)

        code, stdout, stderr = run_kong("migrations finish -f", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        assert.equal("", stderr)

        local code2, stdout2, stderr2 = run_kong("migrations finish -f", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        assert.equal("", stderr)

        assert.equal(code, code2)
        assert.equal(stdout, stdout2)
        assert.equal(stderr, stderr2)
      end)
    end)
  end)

  describe("sanity: make sure postgres server is not overloaded", function()
    local do_it = strategy == "off" and pending or it

    do_it("", function()
      helpers.wait_until(function()
        local ok, err = pcall(init_db)
        if err then
          print(err)
        end
        return ok
      end, 30, 1)
    end)

  end)

end

