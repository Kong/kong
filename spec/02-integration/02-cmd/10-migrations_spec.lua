local helpers = require "spec.helpers"
local pl_utils = require "pl.utils"
local DB = require "kong.db.init"


-- Current number of migrations to execute in a new install
-- additional 1 for EE
local nr_migrations = 1 + 1 -- 11


local lua_path = [[ KONG_LUA_PATH_OVERRIDE="./spec/fixtures/migrations/?.lua;]] ..
                 [[./spec/fixtures/migrations/?/init.lua;]]..
                 [[./spec/fixtures/custom_plugins/?.lua;]]..
                 [[./spec/fixtures/custom_plugins/?/init.lua;" ]]


for _, strategy in helpers.each_strategy() do


  local function run_kong(cmd, env)
    env = env or {}
    env.database = strategy
    env.plugins = env.plugins or "off"

    local cmdline = cmd .. " -c " .. helpers.test_conf_path
    local _, code, stdout, stderr = helpers.kong_exec(cmdline, env, true, lua_path)
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

    describe("reset", function()
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
      it("runs and bootstraps the database", function()
        run_kong("migrations reset --yes")
        local code, stdout = run_kong("migrations bootstrap")
        assert.same(0, code)
        assert.match("\nmigrating core", stdout, 1, true)
        assert.match("\n" .. nr_migrations .. " migration", stdout, 1, true)
        assert.match("\ndatabase is up-to-date\n", stdout, 1, true)
      end)

      it("does not bootstrap twice", function()
        local code = run_kong("migrations bootstrap")
        assert.same(0, code)
        local stdout
        code, stdout = run_kong("migrations bootstrap")
        assert.same(0, code)
        assert.match("database already bootstrapped", stdout, 1, true)
      end)

      pending("-q suppresses all output", function()
        local code, stdout, stderr = run_kong("migrations bootstrap -q")
        assert.same(0, code)
        assert.same(0, #stdout)
        assert.same(0, #stderr)
      end)
    end)

    describe("list", function()
      it("fails if not bootstrapped", function()
        local code = run_kong("migrations reset --yes")
        assert.same(0, code)
        local stdout
        code, stdout = run_kong("migrations list")
        assert.same(3, code)
        assert.match("database needs bootstrapping", stdout, 1, true)
      end)

      it("lists migrations if bootstrapped", function()
        local code = run_kong("migrations bootstrap")
        assert.same(0, code)
        code = run_kong("migrations up")
        assert.same(0, code)
        local stdout
        code, stdout = run_kong("migrations list")

        local db = init_db()
        -- valid CQL and SQL; don't expect to go over one page in CQL here
        local rows = db.connector:query([[SELECT * FROM schema_meta;]])
        local n = 0
        for _, row in ipairs(rows) do
          n = n + #row.executed
        end
        assert.same(nr_migrations, n)

        assert.same(0, code)
        assert.match("executed migrations:", stdout, 1, true)
      end)

      it("lists pending migrations if any", function()
        run_kong("migrations bootstrap")
        local code, stdout = run_kong("migrations list", {
          plugins = "with-migrations",
        })
        assert.same(5, code)
        assert.match("database has new migrations available:\n" ..
                     "session: 000_base_session\n" ..
                     "with-migrations: 000_base_with_migrations, 001_14_to_15",
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
      it("performs first phase of migration", function()
        run_kong("migrations reset --yes")
        local code = run_kong("migrations bootstrap")
        assert.same(0, code)

        local stdout, stderr
        code, stdout, stderr = run_kong("migrations up", {
          plugins = "with-migrations",
        })
        assert.match("3 migrations processed", stdout .. "\n" .. stderr, 1, true)
        assert.match("2 executed", stdout .. "\n" .. stderr, 1, true)
        assert.match("1 pending", stdout .. "\n" .. stderr, 1, true)
        assert.same(0, code)

        code, stdout = run_kong("migrations up")
        assert.same(0, code)
        assert.match("database is already up-to-date", stdout, 1, true)

        local db = init_db()
        -- valid CQL and SQL; don't expect to go over one page in CQL here
        local rows = db.connector:query([[SELECT * FROM schema_meta;]])
        local executed = 0
        local pending = 0
        for _, row in ipairs(rows) do
          executed = executed + #row.executed
          pending = pending + (type(row.pending) == "table" and #row.pending or 0)
        end

        assert.same(nr_migrations + 2, executed)
        assert.same(1, pending)
      end)

      pending("-q suppresses all output", function()
        local code, stdout, stderr = run_kong("migrations up -q")
        assert.same(0, code)
        assert.same(0, #stdout)
        assert.same(0, #stderr)
      end)
    end)

    describe("finish", function()
      it("performs second phase of migration", function()
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
        assert.match("no pending migrations to finish", stdout, 1, true)

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
        assert.same(nr_migrations + 3, executed)
        assert.same(0, pending)
      end)

      pending("-q suppresses all output", function()
        local code, stdout, stderr = run_kong("migrations finish -q")
        assert.same(0, code)
        assert.same(0, #stdout)
        assert.same(0, #stderr)
      end)
    end)
  end)
end
