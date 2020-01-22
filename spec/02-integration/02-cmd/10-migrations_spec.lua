local helpers = require "spec.helpers"
local pl_utils = require "pl.utils"
local utils = require "kong.tools.utils"
local DB = require "kong.db.init"


-- Current number of migrations to execute in a new install
local nr_migrations = 1 -- 11


local lua_path = [[ KONG_LUA_PATH_OVERRIDE="./spec/fixtures/migrations/?.lua;]] ..
                 [[./spec/fixtures/migrations/?/init.lua;]]..
                 [[./spec/fixtures/custom_plugins/?.lua;]]..
                 [[./spec/fixtures/custom_plugins/?/init.lua;" ]]


for _, strategy in helpers.each_strategy() do


  local function run_kong(cmd, env, no_lua_path_overrides)
    env = env or {}
    env.database = strategy
    env.plugins = env.plugins or "off"

    local lpath
    if not no_lua_path_overrides then
      lpath = lua_path
    end

    local cmdline = cmd .. " -c " .. helpers.test_conf_path
    local _, code, stdout, stderr = helpers.kong_exec(cmdline, env, true, lpath)
    return code, stdout, stderr
  end


  local function init_db()
    local db = assert(DB.new(helpers.test_conf, strategy))
    assert(db:init_connector())
    assert(db:connect())
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
          echo y | %s KONG_DATABASE=%s %s migrations reset --v
        ]], lua_path, strategy, helpers.bin_path, helpers.test_conf_path)
        local ok, code, _, stderr = pl_utils.executeex(cmd)
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

      pending("-q suppresses all output", function()
        local code, stdout, stderr = run_kong("migrations bootstrap -q")
        assert.same(0, code)
        assert.same(0, #stdout)
        assert.same(0, #stderr)
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
          local db = init_db()
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
        assert.match("Executed migrations:\n" ..
                     "core: 000_base\n\n" ..
                     "New migrations available:\n" ..
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
        assert.match("2 migrations processed", stdout .. "\n" .. stderr, 1, true)
        assert.match("1 executed", stdout .. "\n" .. stderr, 1, true)
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

        assert.same(nr_migrations + 1, executed)
        assert.same(1, pending)
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
        assert.same(nr_migrations + 2, executed)
        assert.same(0, pending)
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
        if strategy ~= "cassandra" then
          -- cassandra outputs some warnings on duplicate
          -- columns which can safely be ignored
          assert.equal("", stderr)
        end

        code, stdout, stderr = run_kong("migrations up", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        assert.equal("Database is already up-to-date", utils.strip(stdout))
        if strategy ~= "cassandra" then
          -- cassandra outputs some warnings on duplicate
          -- columns which can safely be ignored
          assert.equal("", stderr)
        end

        code, stdout, stderr = run_kong("migrations up -f", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        if strategy ~= "cassandra" then
          -- cassandra outputs some warnings on duplicate
          -- columns which can safely be ignored
          assert.equal("", stderr)
        end

        local code2, stdout2, stderr2 = run_kong("migrations up -f", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        if strategy ~= "cassandra" then
          -- cassandra outputs some warnings on duplicate
          -- columns which can safely be ignored
          assert.equal("", stderr)
        end

        assert.equal(code, code2)
        assert.equal(stdout, stdout2)
        if strategy ~= "cassandra" then
          assert.equal(stderr, stderr2)
        end
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
        if strategy ~= "cassandra" then
          -- cassandra outputs some warnings on duplicate
          -- columns which can safely be ignored
          assert.equal("", stderr)
        end

        code, stdout, stderr = run_kong("migrations up", {
          plugins = "bundled"
        }, true)

        assert.equal(0, code)
        assert.equal("Database is already up-to-date", utils.strip(stdout))
        if strategy ~= "cassandra" then
          -- cassandra outputs some warnings on duplicate
          -- columns which can safely be ignored
          assert.equal("", stderr)
        end

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
        if strategy ~= "cassandra" then
          -- cassandra outputs some warnings on duplicate
          -- columns which can safely be ignored
          assert.equal("", stderr)
        end

        local code2, stdout2, stderr2 = run_kong("migrations finish -f", {
          plugins = "bundled"
        }, true)
        assert.equal(0, code)
        if strategy ~= "cassandra" then
          -- cassandra outputs some warnings on duplicate
          -- columns which can safely be ignored
          assert.equal("", stderr)
        end

        assert.equal(code, code2)
        assert.equal(stdout, stdout2)
        if strategy ~= "cassandra" then
          assert.equal(stderr, stderr2)
        end
      end)
    end)
  end)
end
