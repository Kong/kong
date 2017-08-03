local helpers = require "spec.02-integration.03-dao.helpers"
local Factory = require "kong.dao.factory"
local utils = require "kong.tools.utils"

local api_tbl = {
  name         = "example",
  hosts        = { "example.com" },
  uris         = { "/example" },
  strip_uri    = true,
  upstream_url = "https://example.com",
}

local plugin_tbl = {
  name = "key-auth"
}

helpers.for_each_dao(function(kong_config)
  describe("Model (Constraints) with DB: #" .. kong_config.database, function()
    local plugin_fixture, api_fixture
    local factory, apis, plugins
    setup(function()
      factory = assert(Factory.new(kong_config))
      apis = factory.apis
      plugins = factory.plugins
      assert(factory:run_migrations())

      factory:truncate_tables()
    end)
    before_each(function()
      plugin_fixture = utils.shallow_copy(plugin_tbl)
      local api, err = apis:insert(api_tbl)
      assert.falsy(err)
      api_fixture = api
    end)
    after_each(function()
      factory:truncate_tables()
    end)

    -- Check behavior just in case
    describe("plugins insert()", function()
      it("insert a valid plugin", function()
        plugin_fixture.api_id = api_fixture.id

        local plugin, err = plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.is_table(plugin)
        assert.equal(api_fixture.id, plugin.api_id)
        assert.same({hide_credentials = false, key_names = {"apikey"}, anonymous = "", key_in_body = false,}, plugin.config)
      end)
      it("insert a valid plugin bis", function()
        plugin_fixture.api_id = api_fixture.id
        plugin_fixture.config = {key_names = {"api-key"}}

        local plugin, err = plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.is_table(plugin)
        assert.equal(api_fixture.id, plugin.api_id)
        assert.same({hide_credentials = false, key_names = {"api-key"}, anonymous = "", key_in_body = false}, plugin.config)
      end)
      describe("unique per API/Consumer", function()
        it("API/Plugin", function()
          plugin_fixture.api_id = api_fixture.id

          local plugin, err = plugins:insert(plugin_fixture)
          assert.falsy(err)
          assert.truthy(plugin)

          plugin, err = plugins:insert(plugin_fixture)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.True(err.unique)
          assert.matches("[" .. kong_config.database .. " error] " ..
                         "name=already exists with value 'key-auth'",
                         err, nil, true)
        end)
        it("API/Consumer/Plugin", function()
          local consumer, err = factory.consumers:insert {
            username = "bob"
          }
          assert.falsy(err)
          assert.truthy(consumer)

          local plugin_tbl = {
            name = "rate-limiting",
            api_id = api_fixture.id,
            consumer_id = consumer.id,
            config = {minute = 1}
          }

          local plugin, err = plugins:insert(plugin_tbl)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal(consumer.id, plugin.consumer_id)

          plugin, err = plugins:insert(plugin_tbl)
          assert.truthy(err)
          assert.falsy(plugin)
          assert.True(err.unique)
          assert.matches("[" .. kong_config.database .. " error] " ..
                         "name=already exists with value 'rate-limiting'",
                         err, nil, true)
        end)
      end)
    end)

    describe("FOREIGN constraints", function()

      it("not insert plugin if invalid API foreign key", function()
        plugin_fixture.api_id = utils.uuid()

        local plugin, err = plugins:insert(plugin_fixture)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.foreign)
        assert.matches("api_id=does not exist with value '" .. plugin_fixture.api_id .. "'", tostring(err), nil, true)
      end)
      it("not insert plugin if invalid Consumer foreign key", function()
        local plugin_tbl = {
          name = "rate-limiting",
          api_id = api_fixture.id,
          consumer_id = utils.uuid(),
          config = {minute = 1}
        }

        local plugin, err = plugins:insert(plugin_tbl)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.foreign)
        assert.matches("consumer_id=does not exist with value '" .. plugin_tbl.consumer_id .. "'", tostring(err), nil, true)
      end)
      it("does not update plugin if invalid foreign key", function()
        plugin_fixture.api_id = api_fixture.id

        local plugin, err = plugins:insert(plugin_fixture)
        assert.falsy(err)
        assert.truthy(plugin)

        local fake_api_id = utils.uuid()
        plugin.api_id = fake_api_id
        plugin, err = plugins:update(plugin, {id = plugin.id})
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.foreign)
        assert.matches("api_id=does not exist with value '" .. fake_api_id .. "'", tostring(err), nil, true)
      end)
    end)

    describe("CASCADE delete", function()
      local api_fixture, consumer_fixture
      before_each(function()
        local err
        api_fixture, err = apis:insert {
          name         = "to-delete",
          hosts        = { "to-delete.com" },
          uris         = { "/to-delete" },
          upstream_url = "https://example.com",
        }
        assert.falsy(err)

        consumer_fixture, err = factory.consumers:insert {
          username = "bob"
        }
        assert.falsy(err)
      end)
      after_each(function()
        factory:truncate_tables()
      end)

      it("delete", function()
        local plugin, err = plugins:insert {
          name = "key-auth",
          api_id = api_fixture.id
        }
        assert.falsy(err)

        local res, err = apis:delete(api_fixture)
        assert.falsy(err)
        assert.is_table(res)

        -- no more API
        local api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.falsy(api)

        -- no more plugin
        local plugin, err = plugins:find(plugin)
        assert.falsy(err)
        assert.falsy(plugin)
      end)

      it("delete bis", function()
        local plugin, err = plugins:insert {
          name = "rate-limiting",
          api_id = api_fixture.id,
          consumer_id = consumer_fixture.id,
          config = {minute = 1}
        }
        assert.falsy(err)

        local res, err = factory.consumers:delete(consumer_fixture)
        assert.falsy(err)
        assert.is_table(res)

        local consumer, err = factory.consumers:find(consumer_fixture)
        assert.falsy(err)
        assert.falsy(consumer)

        plugin, err = plugins:find(plugin)
        assert.falsy(err)
        assert.falsy(plugin)
      end)
    end)
  end) -- describe
end) -- for each db
