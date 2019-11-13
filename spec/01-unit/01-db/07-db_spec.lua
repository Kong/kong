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

end)
