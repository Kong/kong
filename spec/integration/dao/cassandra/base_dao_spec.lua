local spec_helper = require "spec.spec_helpers"
local cassandra = require "cassandra"
local constants = require "kong.constants"
local DaoError = require "kong.dao.error"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local uuid = require "uuid"

-- Raw session for double-check purposes
local session
-- Load everything we need from the spec_helper
local env = spec_helper.get_env() -- test environment
local faker = env.faker
local dao_factory = env.dao_factory
local configuration = env.configuration
configuration.cassandra = configuration.databases_available[configuration.database].properties

-- An utility function to apply tests on core collections.
local function describe_core_collections(tests_cb)
  for type, dao in pairs({ api = dao_factory.apis,
                           consumer = dao_factory.consumers }) do
    local collection = type == "plugin" and "plugins" or type.."s"
    describe(collection, function()
      tests_cb(type, collection)
    end)
  end
end

-- An utility function to test if an object is a DaoError.
-- Naming is due to luassert extensibility's restrictions
local function daoError(state, arguments)
  local stub_err = DaoError("", "")
  return getmetatable(stub_err) == getmetatable(arguments[1])
end

local say = require("say")
say:set("assertion.daoError.positive", "Expected %s\nto be a DaoError")
say:set("assertion.daoError.negative", "Expected %s\nto not be a DaoError")
assert:register("assertion", "daoError", daoError, "assertion.daoError.positive", "assertion.daoError.negative")

-- Let's go
describe("Cassandra", function()

  setup(function()
    spec_helper.prepare_db()

    -- Create a parallel session to verify the dao's behaviour
    session = cassandra:new()
    session:set_timeout(configuration.cassandra.timeout)

    local _, err = session:connect(configuration.cassandra.contact_points)
    assert.falsy(err)

    local _, err = session:set_keyspace("kong_tests")
    assert.falsy(err)
  end)

  teardown(function()
    if session then
      local _, err = session:close()
      assert.falsy(err)
    end
  end)

  describe("Base DAO", function()
    describe(":insert()", function()

      it("should error if called with invalid parameters", function()
        assert.has_error(function()
          dao_factory.apis:insert()
        end, "Cannot insert a nil element")

        assert.has_error(function()
          dao_factory.apis:insert("")
        end, "Entity to insert must be a table")
      end)

      it("should insert in DB and let the schema validation add generated values", function()
        -- API
        local api_t = faker:fake_entity("api")
        local api, err = dao_factory.apis:insert(api_t)
        assert.falsy(err)
        assert.truthy(api.id)
        assert.truthy(api.created_at)
        local apis, err = session:execute("SELECT * FROM apis")
        assert.falsy(err)
        assert.True(#apis > 0)
        assert.equal(api.id, apis[1].id)

        -- API
        api, err = dao_factory.apis:insert {
          request_host = "test.com",
          upstream_url = "http://mockbin.com"
        }
        assert.falsy(err)
        assert.truthy(api.name)
        assert.equal("test.com", api.name)

        -- Consumer
        local consumer_t = faker:fake_entity("consumer")
        local consumer, err = dao_factory.consumers:insert(consumer_t)
        assert.falsy(err)
        assert.truthy(consumer.id)
        assert.truthy(consumer.created_at)
        local consumers, err = session:execute("SELECT * FROM consumers")
        assert.falsy(err)
        assert.True(#consumers > 0)
        assert.equal(consumer.id, consumers[1].id)

        -- Plugin configuration
        local plugin_t = {name = "key-auth", api_id = api.id}
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)
        local plugins, err = session:execute("SELECT * FROM plugins")
        assert.falsy(err)
        assert.True(#plugins > 0)
        assert.equal(plugin.id, plugins[1].id)
      end)

      it("should let the schema validation return errors and not insert", function()
        -- Without an api_id, it's a schema error
        local plugin_t = faker:fake_entity("plugin")
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.schema)
        assert.are.same("api_id is required", err.message.api_id)
      end)

      it("should ensure fields with `unique` are unique", function()
        local api_t = faker:fake_entity("api")

        -- Success
        local _, err = dao_factory.apis:insert(api_t)
        assert.falsy(err)

        -- Failure
        local api, err = dao_factory.apis:insert(api_t)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.unique)
        assert.are.same("name already exists with value '"..api_t.name.."'", err.message.name)
        assert.falsy(api)
      end)

      it("should ensure fields with `foreign` are existing", function()
        -- Plugin configuration
        local plugin_t = faker:fake_entity("plugin")
        plugin_t.api_id = uuid()

        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.foreign)
        assert.are.same("api_id "..plugin_t.api_id.." does not exist", err.message.api_id)
      end)

      it("should do insert checks for entities with `self_check`", function()
        local api, err = dao_factory.apis:insert(faker:fake_entity("api"))
        assert.falsy(err)
        assert.truthy(api.id)

        local plugin_t = faker:fake_entity("plugin")
        plugin_t.api_id = api.id

        -- Success: plugin doesn't exist yet
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)

        -- Failure: the same plugin is already inserted
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.unique)
        assert.are.same("Plugin configuration already exists", err.message)
      end)

    end) -- describe :insert()

    describe(":update()", function()

      it("should error if called with invalid parameters", function()
        assert.has_error(function()
          dao_factory.apis:update()
        end, "Cannot update a nil element")

        assert.has_error(function()
          dao_factory.apis:update("")
        end, "Entity to update must be a table")
      end)

      it("should return nil and no error if no entity was found to update in DB", function()
        local api_t = faker:fake_entity("api")
        api_t.id = uuid()

        -- No entity to update
        local entity, err = dao_factory.apis:update(api_t)
        assert.falsy(entity)
        assert.falsy(err)
      end)

      it("should consider no entity to be found if an empty table is given to it", function()
        local api, err = dao_factory.apis:update({})
        assert.falsy(err)
        assert.falsy(api)
      end)

      it("should update specified, non-primary fields in DB", function()
        -- API
        local apis, err = session:execute("SELECT * FROM apis")
        assert.falsy(err)
        assert.True(#apis > 0)

        local api_t = apis[1]
        api_t.name = api_t.name.."-updated"

        local api, err = dao_factory.apis:update(api_t)
        assert.falsy(err)
        assert.truthy(api)

        apis, err = session:execute("SELECT * FROM apis WHERE name = ?", {api_t.name})
        assert.falsy(err)
        assert.equal(1, #apis)
        assert.equal(api_t.id, apis[1].id)
        assert.equal(api_t.name, apis[1].name)
        assert.equal(api_t.request_host, apis[1].request_host)
        assert.equal(api_t.upstream_url, apis[1].upstream_url)

        -- Consumer
        local consumers, err = session:execute("SELECT * FROM consumers")
        assert.falsy(err)
        assert.True(#consumers > 0)

        local consumer_t = consumers[1]
        consumer_t.custom_id = consumer_t.custom_id.."updated"

        local consumer, err = dao_factory.consumers:update(consumer_t)
        assert.falsy(err)
        assert.truthy(consumer)

        consumers, err = session:execute("SELECT * FROM consumers WHERE custom_id = ?", {consumer_t.custom_id})
        assert.falsy(err)
        assert.equal(1, #consumers)
        assert.equal(consumer_t.name, consumers[1].name)

        -- Plugin Configuration
        local plugins, err = session:execute("SELECT * FROM plugins")
        assert.falsy(err)
        assert.True(#plugins > 0)

        local plugin_t = plugins[1]
        plugin_t.config = cjson.decode(plugin_t.config)
        plugin_t.enabled = false
        local plugin, err = dao_factory.plugins:update(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)

        plugins, err = session:execute("SELECT * FROM plugins WHERE id = ?", {cassandra.uuid(plugin_t.id)})
        assert.falsy(err)
        assert.equal(1, #plugins)
      end)

      it("should ensure fields with `unique` are unique", function()
        local apis, err = session:execute("SELECT * FROM apis")
        assert.falsy(err)
        assert.True(#apis > 0)

        local api_t = apis[1]
        -- Should not work because we're reusing a request_host
        api_t.request_host = apis[2].request_host

        local api, err = dao_factory.apis:update(api_t)
        assert.truthy(err)
        assert.falsy(api)
        assert.is_daoError(err)
        assert.True(err.unique)
        assert.equal("request_host already exists with value '"..api_t.request_host.."'", err.message.request_host)
      end)

      describe("full", function()

        it("should set to NULL if a field is not specified", function()
          local api_t = faker:fake_entity("api")
          api_t.request_path = "/request_path"

          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(err)
          assert.truthy(api_t.request_path)

          -- Update
          api.request_path = nil
          api, err = dao_factory.apis:update(api, true)
          assert.falsy(err)
          assert.truthy(api)
          assert.falsy(api.request_path)

          -- Check update
          api, err = session:execute("SELECT * FROM apis WHERE id = ?", {cassandra.uuid(api.id)})
          assert.falsy(err)
          assert.falsy(api.request_path)
        end)

        it("should still check the validity of the schema", function()
          local api_t = faker:fake_entity("api")

          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(err)
          assert.truthy(api_t)

          -- Update
          api.request_host = nil

          local nil_api, err = dao_factory.apis:update(api, true)
          assert.truthy(err)
          assert.falsy(nil_api)

          -- Check update failed
          api, err = session:execute("SELECT * FROM apis WHERE id = ?", {cassandra.uuid(api.id)})
          assert.falsy(err)
          assert.truthy(api[1].name)
          assert.truthy(api[1].request_host)
        end)

      end)
    end) -- describe :update()

    describe(":find_by_keys()", function()
      describe_core_collections(function(type, collection)

        it("should error if called with invalid parameters", function()
          assert.has_error(function()
            dao_factory[collection]:find_by_keys("")
          end, "where_t must be a table")
        end)

        it("should handle empty search fields", function()
          local results, err = dao_factory[collection]:find_by_keys({})
          assert.falsy(err)
          assert.truthy(results)
          assert.True(#results > 0)
        end)

        it("should handle nil search fields", function()
          local results, err = dao_factory[collection]:find_by_keys(nil)
          assert.falsy(err)
          assert.truthy(results)
          assert.True(#results > 0)
        end)
      end)

      it("should query an entity from the given fields and return if filtering was needed", function()
        -- Filtering needed
        local apis, err = session:execute("SELECT * FROM apis")
        assert.falsy(err)
        assert.True(#apis > 0)

        local api_t = apis[1]
        local apis, err, needs_filtering = dao_factory.apis:find_by_keys(api_t)
        assert.falsy(err)
        assert.same(api_t, apis[1])
        assert.True(needs_filtering)

        -- No Filtering needed
        apis, err, needs_filtering = dao_factory.apis:find_by_keys {request_host = api_t.request_host}
        assert.falsy(err)
        assert.same(api_t, apis[1])
        assert.False(needs_filtering)
      end)

    end) -- describe :find_by_keys()

    describe(":find()", function()

      setup(function()
        spec_helper.drop_db()
        spec_helper.seed_db(10)
      end)

      describe_core_collections(function(type, collection)

        it("should find entities", function()
          local entities, err = session:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(entities)
          assert.True(#entities > 0)

          local results, err = dao_factory[collection]:find()
          assert.falsy(err)
          assert.truthy(results)
          assert.same(#entities, #results)
        end)

        it("should allow pagination", function()
          -- 1st page
          local rows_1, err = dao_factory[collection]:find(2)
          assert.falsy(err)
          assert.truthy(rows_1)
          assert.same(2, #rows_1)
          assert.truthy(rows_1.next_page)

          -- 2nd page
          local rows_2, err = dao_factory[collection]:find(2, rows_1.next_page)
          assert.falsy(err)
          assert.truthy(rows_2)
          assert.same(2, #rows_2)
        end)

      end)
    end) -- describe :find()

    describe(":find_by_primary_key()", function()
      describe_core_collections(function(type, collection)

        it("should error if called with invalid parameters", function()
          assert.has_error(function()
            dao_factory[collection]:find_by_primary_key("")
          end, "where_t must be a table")
        end)

        it("should return nil (not found) if where_t is empty", function()
          local res, err = dao_factory[collection]:find_by_primary_key({})
          assert.falsy(err)
          assert.falsy(res)
        end)

      end)

      it("should find one entity by its primary key", function()
        local apis, err = session:execute("SELECT * FROM apis")
        assert.falsy(err)
        assert.True(#apis > 0)

        local api, err = dao_factory.apis:find_by_primary_key { id = apis[1].id }
        assert.falsy(err)
        assert.truthy(apis)
        assert.same(apis[1], api)
      end)

      it("should handle an invalid uuid value", function()
        local apis, err = dao_factory.apis:find_by_primary_key { id = "abcd" }
        assert.falsy(apis)
        assert.True(err.invalid_type)
        assert.equal("abcd is an invalid uuid", err.message.id)
      end)

      describe("plugins", function()

        setup(function()
          local fixtures = spec_helper.seed_db(1)
          faker:insert_from_table {
            plugin = {
              { name = "key-auth", config = {key_names = {"apikey"}}, api_id = fixtures.api[1].id }
            }
          }
        end)

        it("should unmarshall the `config` field", function()
          local plugins, err = session:execute("SELECT * FROM plugins")
          assert.falsy(err)
          assert.truthy(plugins)
          assert.True(#plugins> 0)

          local plugin_t = plugins[1]

          local plugin, err = dao_factory.plugins:find_by_primary_key {
            id = plugin_t.id,
            name = plugin_t.name
          }
          assert.falsy(err)
          assert.truthy(plugin)
          assert.equal("table", type(plugin.config))
        end)

      end)
    end) -- describe :find_by_primary_key()

    describe(":delete()", function()

      teardown(function()
        spec_helper.drop_db()
      end)

      describe_core_collections(function(type, collection)

        it("should error if called with invalid parameters", function()
          assert.has_error(function()
            dao_factory[collection]:delete("")
          end, "where_t must be a table")
        end)

        it("should return false if entity to delete wasn't found", function()
          local ok, err = dao_factory[collection]:delete({id = uuid()})
          assert.falsy(err)
          assert.False(ok)
        end)

        it("should delete an entity based on its primary key", function()
          local entities, err = session:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(entities)
          assert.True(#entities > 0)

          local ok, err = dao_factory[collection]:delete(entities[1])
          assert.falsy(err)
          assert.True(ok)

          local entities, err = session:execute("SELECT * FROM "..collection.." WHERE id = ?", {cassandra.uuid(entities[1].id)})
          assert.falsy(err)
          assert.truthy(entities)
          assert.are.same(0, #entities)
        end)

      end)
    end)

    --
    -- APIs additional behaviour
    --

    describe("APIs", function()

      setup(function()
        spec_helper.seed_db(100)
      end)

      describe(":find_all()", function()
        local apis, err = dao_factory.apis:find_all()
        assert.falsy(err)
        assert.truthy(apis)
        assert.equal(100, #apis)
      end)
    end)

    --
    -- Plugins configuration additional behaviour
    --

    describe("plugins", function()
      describe(":find_distinct()", function()
        it("should find distinct plugins configurations", function()
          faker:insert_from_table {
            api = {
              { name = "tests-distinct-1", request_host = "foo.com", upstream_url = "http://mockbin.com" },
              { name = "tests-distinct-2", request_host = "bar.com", upstream_url = "http://mockbin.com" }
            },
            plugin = {
              { name = "key-auth", config = {key_names = {"apikey"}, hide_credentials = true}, __api = 1 },
              { name = "rate-limiting", config = { minute = 6}, __api = 1 },
              { name = "rate-limiting", config = { minute = 6}, __api = 2 },
              { name = "file-log", config = { path = "/tmp/spec.log" }, __api = 1 }
            }
          }

          local res, err = dao_factory.plugins:find_distinct()

          assert.falsy(err)
          assert.truthy(res)

          assert.are.same(3, #res)
          assert.truthy(utils.table_contains(res, "key-auth"))
          assert.truthy(utils.table_contains(res, "rate-limiting"))
          assert.truthy(utils.table_contains(res, "file-log"))
        end)
      end)

      describe(":insert()", function()
        local api_id
        local inserted_plugin
        it("should insert a plugin and set the consumer_id to a 'null' uuid if none is specified", function()
          -- Since we want to specifically select plugins configurations which have _no_ consumer_id sometimes, we cannot rely on using
          -- NULL (and thus, not inserting the consumer_id column for the row). To fix this, we use a predefined, nullified uuid...

          -- Create an API
          local api_t = faker:fake_entity("api")
          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(err)

          local plugin_t = faker:fake_entity("plugin")
          plugin_t.api_id = api.id

          local plugin, err = dao_factory.plugins:insert(plugin_t)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.falsy(plugin.consumer_id)

          -- for next test
          api_id = api.id
          inserted_plugin = plugin
          inserted_plugin.consumer_id = nil
        end)

        it("should insert a plugin with an empty config if none is specified", function()
          local api_t = faker:fake_entity("api")
          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(err)
          assert.truthy(api)

          local plugin, err = dao_factory.plugins:insert({
            name = "request-transformer",
            api_id = api.id
          })

          assert.falsy(err)
          assert.truthy(plugin)
          assert.falsy(plugin.consumer_id)
          assert.same("request-transformer", plugin.name)
          assert.same({}, plugin.config)
        end)

        it("should select a plugin configuration by 'null' uuid consumer_id and remove the column", function()
          -- Now we should be able to select this plugin
          local rows, err = dao_factory.plugins:find_by_keys {
            api_id = api_id,
            consumer_id = constants.DATABASE_NULL_ID
          }
          assert.falsy(err)
          assert.truthy(rows[1])
          assert.same(inserted_plugin, rows[1])
          assert.falsy(rows[1].consumer_id)
        end)
      end)

    end) -- describe plugins configurations
  end) -- describe Base DAO
end) -- describe Cassandra
