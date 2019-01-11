local mocker = require("spec.fixtures.mocker")


local function setup_it_block()
  mocker.setup(finally, {
    modules = {
      {"kong.db.strategies", {
        new = function()
          local connector = {
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

      -- calling last_schema_state returns the same object
      assert(state == last_state)

      local last_state_2 = db:last_schema_state()

      -- calling it again returns the same object
      assert(state == last_state_2)

      local state_2 = db:schema_state()
      assert.is_table(state_2)

      -- schema_state always returns a new object
      assert(state ~= state_2)

      local last_state_3 = db:last_schema_state()

      -- the latest object created by schema_state is the one cached
      assert(state_2 == last_state_3)

    end)

  end)

end)
