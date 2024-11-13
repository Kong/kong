local mocker = require("spec.fixtures.mocker")


local function setup_it_block()
  mocker.setup(finally, {
    modules = {
      {"kong.db.strategies", {
        new = function()
          local connector = {
            defaults = {
              pagination = {
                page_size     = 1000,
                max_page_size = 50000,
              },
            },
            infos = function()
              return {}
            end,
            connect_migrations = function()
              return true
            end,
            schema_migrations = function()
              return {}
            end,
            is_014 = function()
              return { is_014 = false }
            end,
            close = function()
            end,
          }
          local strategies = mocker.table_where_every_key_returns({})
          return connector, strategies
        end,
      }},
      {"kong.db", {}},
    }
  })
end


describe("DB", function()

  describe("schema_state", function()

    it("returns the state of migrations", function()
      setup_it_block()

      local DB = require("kong.db")

      local kong_config = {
        loaded_plugins = {},
      }
      local db, err = DB.new(kong_config, "mock")
      assert.is_nil(err)
      assert.is_table(db)

      local state = db:schema_state()
      assert.is_table(state)
    end)

  end)

  describe("last_schema_state", function()

    it("returns the last fetched state of migrations", function()
      setup_it_block()

      local DB = require("kong.db")

      local kong_config = {
        loaded_plugins = {},
      }
      local db, err = DB.new(kong_config, "mock")
      assert.is_nil(err)
      assert.is_table(db)

      local state = db:schema_state()
      assert.is_table(state)

      local last_state = db:last_schema_state()

      assert(state == last_state,
             "expected that calling last_schema_state returned " ..
             "the same object as schema_state")

      local last_state_2 = db:last_schema_state()

      assert(state == last_state_2,
             "expected that calling last_schema_state twice " ..
             "returns the same object")

      local state_2 = db:schema_state()
      assert.is_table(state_2)

      assert(state ~= state_2,
             "expected schema_state to always return a new object")

      local last_state_3 = db:last_schema_state()

      assert(state_2 == last_state_3,
             "expected the object returned by last_schema_state " ..
             "to be the latest created by schema_state")

    end)

  end)

  describe(":check_version_compat()", function()
    local db = {
      strategy = "foobar",
      connector = { },
    }

    lazy_setup(function()
      local DB = require("kong.db")
      db.check_version_compat = DB.check_version_compat
    end)

    describe("db_ver < min", function()
      it("errors", function()
        local versions_to_test = {
          "1.0",
          "9.0",
          "9.3",
        }

        for _, v in ipairs(versions_to_test) do
          db.connector.major_minor_version = v

          local ok, err = db:check_version_compat("10.0")
          assert.is_false(ok)
          assert.equal("Kong requires " .. db.strategy .. " 10.0 or greater " ..
                       "(currently using " .. v .. ")", err)
        end
      end)
    end)

    describe("db_ver < deprecated < min", function()
      it("errors", function()
        local versions_to_test = {
          "1.0",
          "9.0",
          "9.3",
        }

        for _, v in ipairs(versions_to_test) do
          db.connector.major_minor_version = v

          local ok, err = db:check_version_compat("10.0", "9.4")
          assert.is_false(ok)
          assert.equal("Kong requires " .. db.strategy .. " 10.0 or greater " ..
                       "(currently using " .. v .. ")", err)
        end
      end)
    end)

    describe("deprecated <= db_ver < min", function()
      it("logs deprecation warning", function()
        local log = require "kong.cmd.utils.log"
        local s = spy.on(log, "warn")

        local versions_to_test = {
          "9.3",
          "9.4",
        }

        for _, v in ipairs(versions_to_test) do
          db.connector.major_minor_version = v

          local ok, err = db:check_version_compat("9.5", "9.3")
          assert.is_nil(err)
          assert.is_true(ok) -- no error on deprecation notices
          assert.spy(s).was_called_with(
            "Currently using %s %s which is considered deprecated, " ..
            "please use %s or greater", db.strategy, v, "9.5")
        end
      end)
    end)

    describe("min < deprecated <= db_ver", function()
      -- Note: constants should not be configured in this fashion, but this
      -- test is for robustness's sake
      it("fine", function()
        local versions_to_test = {
          "10.0",
          "11.1",
        }

        for _, v in ipairs(versions_to_test) do
          db.connector.major_minor_version = v

          local ok, err = db:check_version_compat("9.4", "10.0")
          assert.is_nil(err)
          assert.is_true(ok)
        end
      end)
    end)

    describe("deprecated < min <= db_ver", function()
      it("fine", function()
        local versions_to_test = {
          "9.5",
          "10.0",
          "11.1",
        }

        for _, v in ipairs(versions_to_test) do
          db.connector.major_minor_version = v

          local ok, err = db:check_version_compat("9.5", "9.4")
          assert.is_nil(err)
          assert.is_true(ok)
        end
      end)
    end)

  end)

end)
