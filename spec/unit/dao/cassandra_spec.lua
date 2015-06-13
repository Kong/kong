local CassandraFactory = require "kong.dao.cassandra.factory"
local spec_helper = require "spec.spec_helpers"
local timestamp = require "kong.tools.timestamp"
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
    local collection = type == "plugin_configuration" and "plugins_configurations" or type.."s"
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
describe("Cassandra DAO", function()

  setup(function()
    spec_helper.prepare_db()

    -- Create a parallel session to verify the dao's behaviour
    session = cassandra.new()
    session:set_timeout(configuration.cassandra.timeout)

    local _, err = session:connect(configuration.cassandra.hosts, configuration.cassandra.port)
    assert.falsy(err)

    local _, err = session:set_keyspace(configuration.cassandra.keyspace)
    assert.falsy(err)
  end)

  teardown(function()
    if session then
      local _, err = session:close()
      assert.falsy(err)
    end
  end)

  describe("Collections schemas", function()

    describe_core_collections(function(type, collection)

      it("should have statements for all unique and foreign schema fields", function()
        for column, schema_field in pairs(dao_factory[collection]._schema) do
          if schema_field.unique then
            assert.truthy(dao_factory[collection]._queries.__unique[column])
          end
          if schema_field.foreign then
            assert.truthy(dao_factory[collection]._queries.__foreign[column])
          end
        end
      end)

    end)
  end)

  describe("Factory", function()

    describe(":prepare()", function()

      it("should prepare all queries in collection's _queries", function()
        local new_factory = CassandraFactory({ hosts = "127.0.0.1",
                                               port = 9042,
                                               timeout = 1000,
                                               keyspace = configuration.cassandra.keyspace
        })

        local err = new_factory:prepare()
        assert.falsy(err)

        -- assert collections have prepared statements
        for _, collection in ipairs({ "apis", "consumers" }) do
          for k, v in pairs(new_factory[collection]._queries) do
            local cache_key
            if type(v) == "string" then
              cache_key = v
            elseif v.query then
              cache_key = v.query
            end

            if cache_key then
              assert.truthy(new_factory[collection]._statements_cache[cache_key])
            end
          end
        end
      end)

      it("should raise an error if cannot connect to Cassandra", function()
        local new_factory = CassandraFactory({ hosts = "127.0.0.1",
                                               port = 45678,
                                               timeout = 1000,
                                               keyspace = configuration.cassandra.keyspace
        })

        local err = new_factory:prepare()
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.database)
        assert.are.same("Cassandra error: connection refused", err.message)
      end)

    end)
  end) -- describe Factory

  --
  -- Core DAO Collections (consumers, apis, plugins_configurations)
  --

  describe("Collections", function()

    describe(":insert()", function()

      describe("APIs", function()

        it("should insert in DB and add generated values", function()
          local api_t = faker:fake_entity("api")
          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(err)
          assert.truthy(api.id)
          assert.truthy(api.created_at)
        end)

        it("should use the public_dns as the name if none is specified", function()
          local api, err = dao_factory.apis:insert {
            public_dns = "test.com",
            target_url = "http://mockbin.com"
          }
          assert.falsy(err)
          assert.truthy(api.name)
          assert.are.same("test.com", api.name)
        end)

        it("should not insert an invalid api", function()
          -- Nil
          local api, err = dao_factory.apis:insert()
          assert.falsy(api)
          assert.truthy(err)
          assert.True(err.schema)
          assert.are.same("Cannot insert a nil element", err.message)

          -- Invalid schema UNIQUE error (already existing API name)
          local api_rows, err = session:execute("SELECT * FROM apis LIMIT 1;")
          assert.falsy(err)
          local api_t = faker:fake_entity("api")
          api_t.name = api_rows[1].name

          local api, err = dao_factory.apis:insert(api_t)
          assert.truthy(err)
          assert.is_daoError(err)
          assert.True(err.unique)
          assert.are.same("name already exists with value '"..api_t.name.."'", err.message.name)
          assert.falsy(api)

          -- Duplicated name
          local apis, err = session:execute("SELECT * FROM apis")
          assert.falsy(err)
          assert.truthy(#apis > 0)

          local api_t = faker:fake_entity("api")
          api_t.name = apis[1].name
          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(api)
          assert.truthy(err)
          assert.is_daoError(err)
          assert.True(err.unique)
          assert.are.same("name already exists with value '"..api_t.name.."'", err.message.name)
        end)

      end)

      describe("Consumers", function()

        it("should insert an consumer in DB and add generated values", function()
          local consumer_t = faker:fake_entity("consumer")
          local consumer, err = dao_factory.consumers:insert(consumer_t)
          assert.falsy(err)
          assert.truthy(consumer.id)
          assert.truthy(consumer.created_at)
        end)

      end)

      describe("plugin_configurations", function()

        it("should not insert in DB if invalid", function()
          -- Without an api_id, it's a schema error
          local plugin_t = faker:fake_entity("plugin_configuration")
          local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
          assert.falsy(plugin)
          assert.truthy(err)
          assert.is_daoError(err)
          assert.True(err.schema)
          assert.are.same("api_id is required", err.message.api_id)

          -- With an invalid api_id, it's an FOREIGN error
          local plugin_t = faker:fake_entity("plugin_configuration")
          plugin_t.api_id = uuid()

          local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
          assert.falsy(plugin)
          assert.truthy(err)
          assert.is_daoError(err)
          assert.True(err.foreign)
          assert.are.same("api_id "..plugin_t.api_id.." does not exist", err.message.api_id)

          -- With invalid api_id and consumer_id, it's an EXISTS error
          local plugin_t = faker:fake_entity("plugin_configuration")
          plugin_t.api_id = uuid()
          plugin_t.consumer_id = uuid()

          local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
          assert.falsy(plugin)
          assert.truthy(err)
          assert.is_daoError(err)
          assert.True(err.foreign)
          assert.are.same("api_id "..plugin_t.api_id.." does not exist", err.message.api_id)
          assert.are.same("consumer_id "..plugin_t.consumer_id.." does not exist", err.message.consumer_id)
        end)

        it("should insert a plugin configuration in DB and add generated values", function()
          local api_t = faker:fake_entity("api")
          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(err)

          local consumers, err = session:execute("SELECT * FROM consumers")
          assert.falsy(err)
          assert.True(#consumers > 0)

          local plugin_t = faker:fake_entity("plugin_configuration")
          plugin_t.api_id = api.id
          plugin_t.consumer_id = consumers[1].id

          local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
          assert.falsy(err)
          assert.truthy(plugin)
          assert.truthy(plugin.consumer_id)
        end)

        it("should not insert twice a plugin with same api_id, consumer_id and name", function()
          -- Insert a new API for a fresh start
          local api, err = dao_factory.apis:insert(faker:fake_entity("api"))
          assert.falsy(err)
          assert.truthy(api.id)

          local consumers, err = session:execute("SELECT * FROM consumers")
          assert.falsy(err)
          assert.True(#consumers > 0)

          local plugin_t = faker:fake_entity("plugin_configuration")
          plugin_t.api_id = api.id
          plugin_t.consumer_id = consumers[#consumers].id

          -- This should work
          local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
          assert.falsy(err)
          assert.truthy(plugin)

          -- This should fail
          local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
          assert.falsy(plugin)
          assert.truthy(err)
          assert.is_daoError(err)
          assert.True(err.unique)
          assert.are.same("Plugin configuration already exists", err.message)
        end)

        it("should not insert a plugin if this plugin doesn't exist (not installed)", function()
          local plugin_t = faker:fake_entity("plugin_configuration")
          plugin_t.name = "world domination plugin"

          -- This should fail
          local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
          assert.falsy(plugin)
          assert.truthy(err)
          assert.is_daoError(err)
          assert.are.same("Plugin \"world domination plugin\" not found", err.message.value)
        end)

        it("should validate a plugin value schema", function()
          -- Success
          -- Insert a new API for a fresh start
          local api, err = dao_factory.apis:insert(faker:fake_entity("api"))
          assert.falsy(err)
          assert.truthy(api.id)

          local consumers, err = session:execute("SELECT * FROM consumers")
          assert.falsy(err)
          assert.True(#consumers > 0)

          local plugin_t =  {
            api_id = api.id,
            consumer_id = consumers[#consumers].id,
            name = "keyauth",
            value = {
              key_names = { "x-kong-key" }
            }
          }

          local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
          assert.falsy(err)
          assert.truthy(plugin)

          local ok, err = dao_factory.plugins_configurations:delete({id = plugin.id})
          assert.True(ok)
          assert.falsy(err)

          -- Failure
          plugin_t.name = "ratelimiting"
          plugin_t.value = { period = "hello" }
          local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
          assert.truthy(err)
          assert.is_daoError(err)
          assert.truthy(err.schema)
          assert.are.same("\"hello\" is not allowed. Allowed values are: \"second\", \"minute\", \"hour\", \"day\", \"month\", \"year\"", err.message["value.period"])
          assert.falsy(plugin)
        end)

      end)
    end) -- describe :insert()

    describe(":update()", function()

      describe_core_collections(function(type, collection)

        it("should return nil if no entity was found to update in DB", function()
          local t = faker:fake_entity(type)
          t.id = uuid()

          -- Remove immutable fields
          for k,v in pairs(dao_factory[collection]._schema) do
            if v.immutable and not v.required then
              t[k] = nil
            end
          end

          -- No entity to update
          local entity, err = dao_factory[collection]:update(t)
          assert.falsy(entity)
          assert.falsy(err)
        end)

      end)

      describe("APIs", function()

        -- Cassandra sets to NULL unset fields specified in an UPDATE query
        -- https://issues.apache.org/jira/browse/CASSANDRA-7304
        it("should update in DB without setting to NULL unset fields", function()
          local apis, err = session:execute("SELECT * FROM apis")
          assert.falsy(err)
          assert.True(#apis > 0)

          local api_t = apis[1]
          api_t.name = api_t.name.." updated"

          -- This should not set those values to NULL in DB
          api_t.created_at = nil
          api_t.public_dns = nil
          api_t.target_url = nil

          local api, err = dao_factory.apis:update(api_t)
          assert.falsy(err)
          assert.truthy(api)

          local apis, err = session:execute("SELECT * FROM apis WHERE name = '"..api_t.name.."'")
          assert.falsy(err)
          assert.are.same(1, #apis)
          assert.truthy(apis[1].id)
          assert.truthy(apis[1].created_at)
          assert.truthy(apis[1].public_dns)
          assert.truthy(apis[1].target_url)
          assert.are.same(api_t.name, apis[1].name)
        end)

        it("should prevent the update if the UNIQUE check fails", function()
          local apis, err = session:execute("SELECT * FROM apis")
          assert.falsy(err)
          assert.True(#apis > 0)

          local api_t = apis[1]
          api_t.name = api_t.name.." unique update attempt"

          -- Should not work because UNIQUE check fails
          api_t.public_dns = apis[2].public_dns

          local api, err = dao_factory.apis:update(api_t)
          assert.falsy(api)
          assert.truthy(err)
          assert.is_daoError(err)
          assert.True(err.unique)
          assert.are.same("public_dns already exists with value '"..api_t.public_dns.."'", err.message.public_dns)
        end)

      end)

      describe("Consumers", function()

        it("should update in DB if entity can be found", function()
          local consumers, err = session:execute("SELECT * FROM consumers")
          assert.falsy(err)
          assert.True(#consumers > 0)

          local consumer_t = consumers[1]

          -- Should be correctly updated in DB
          consumer_t.custom_id = consumer_t.custom_id.."updated"

          local consumer, err = dao_factory.consumers:update(consumer_t)
          assert.falsy(err)
          assert.truthy(consumer)

          local consumers, err = session:execute("SELECT * FROM consumers WHERE custom_id = '"..consumer_t.custom_id.."'")
          assert.falsy(err)
          assert.True(#consumers == 1)
          assert.are.same(consumer_t.name, consumers[1].name)
        end)

      end)

      describe("plugin_configurations", function()

        setup(function()
          local fixtures = spec_helper.seed_db(1)
          faker:insert_from_table {
            plugin_configuration = {
              { name = "keyauth", value = {key_names = {"apikey"}}, api_id = fixtures.api[1].id }
            }
          }
        end)

        it("should update in DB if entity can be found", function()
          local plugins_configurations, err = session:execute("SELECT * FROM plugins_configurations")
          assert.falsy(err)
          assert.True(#plugins_configurations > 0)

          local plugin_conf_t = plugins_configurations[1]
          plugin_conf_t.value = cjson.decode(plugin_conf_t.value)
          plugin_conf_t.enabled = false
          local plugin_conf, err = dao_factory.plugins_configurations:update(plugin_conf_t)
          assert.falsy(err)
          assert.truthy(plugin_conf)

          local plugins_configurations, err = session:execute("SELECT * FROM plugins_configurations WHERE id = ?", { cassandra.uuid(plugin_conf_t.id) })
          assert.falsy(err)
          assert.are.same(1, #plugins_configurations)
        end)

      end)
    end) -- describe :update()

    describe(":delete()", function()

      describe_core_collections(function(type, collection)

        it("should return false if there was nothing to delete", function()
          local ok, err = dao_factory[collection]:delete({id = uuid()})
          assert.is_not_true(ok)
          assert.falsy(err)
        end)

        it("should delete an entity if it can be found", function()
          local entities, err = session:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(entities)
          assert.True(#entities > 0)

          local ok, err = dao_factory[collection]:delete({id = entities[1].id})
          assert.falsy(err)
          assert.True(ok)

          local entities, err = session:execute("SELECT * FROM "..collection.." WHERE id = "..entities[1].id )
          assert.falsy(err)
          assert.truthy(entities)
          assert.are.same(0, #entities)
        end)

      end)

      describe("APIs", function()
        local api, untouched_api

        setup(function()
          spec_helper.drop_db()

          -- Insert an API
          local _, err
          api, err = dao_factory.apis:insert {
            name = "cascade delete test",
            public_dns = "cascade.com",
            target_url = "http://mockbin.com"
          }
          assert.falsy(err)

          -- Insert some plugins_configurations
          _, err = dao_factory.plugins_configurations:insert {
            name = "keyauth", value = { key_names = {"apikey"} }, api_id = api.id
          }
          assert.falsy(err)

          _, err = dao_factory.plugins_configurations:insert {
            name = "ratelimiting", value = { period = "minute", limit = 6 }, api_id = api.id
          }
          assert.falsy(err)

          _, err = dao_factory.plugins_configurations:insert {
            name = "filelog", value = { path = "/tmp/spec.log" }, api_id = api.id
          }
          assert.falsy(err)

          -- Insert an unrelated API + plugin
          untouched_api, err = dao_factory.apis:insert {
            name = "untouched cascade test api",
            public_dns = "untouched.com",
            target_url = "http://mockbin.com"
          }
          assert.falsy(err)

          _, err = dao_factory.plugins_configurations:insert {
            name = "filelog", value = { path = "/tmp/spec.log" }, api_id = untouched_api.id
          }
          assert.falsy(err)

          -- Make sure we have 3 matches
          local results, err = dao_factory.plugins_configurations:find_by_keys {
            api_id = api.id
          }
          assert.falsy(err)
          assert.are.same(3, #results)
        end)

        teardown(function()
          spec_helper.drop_db()
        end)

        it("should delete all related plugins_configurations when deleting an API", function()
          local ok, err = dao_factory.apis:delete(api)
          assert.falsy(err)
          assert.True(ok)

          -- Make sure we have 0 matches
          local results, err = dao_factory.plugins_configurations:find_by_keys {
            api_id = api.id
          }
          assert.falsy(err)
          assert.are.same(0, #results)

          -- Make sure the untouched API still has its plugin
          local results, err = dao_factory.plugins_configurations:find_by_keys {
            api_id = untouched_api.id
          }
          assert.falsy(err)
          assert.are.same(1, #results)
        end)

      end)

      describe("Consumers", function()
        local api, consumer, untouched_consumer

        setup(function()
          spec_helper.drop_db()

          local _, err

          -- Insert a Consumer
          consumer, err = dao_factory.consumers:insert { username = "king kong" }
          assert.falsy(err)

          -- Insert an API
          api, err = dao_factory.apis:insert {
            name = "cascade delete test",
            public_dns = "cascade.com",
            target_url = "http://mockbin.com"
          }
          assert.falsy(err)

          -- Insert some plugins_configurations
          _, err = dao_factory.plugins_configurations:insert {
            name="keyauth", value = { key_names = {"apikey"} }, api_id = api.id,
            consumer_id = consumer.id
          }
          assert.falsy(err)

          _, err = dao_factory.plugins_configurations:insert {
            name = "ratelimiting", value = { period = "minute", limit = 6 }, api_id = api.id,
            consumer_id = consumer.id
          }
          assert.falsy(err)

          _, err = dao_factory.plugins_configurations:insert {
            name = "filelog", value = { path = "/tmp/spec.log" }, api_id = api.id,
            consumer_id = consumer.id
          }
          assert.falsy(err)

          -- Inser an untouched consumer + plugin
          untouched_consumer, err = dao_factory.consumers:insert { username = "untouched consumer" }
          assert.falsy(err)

          _, err = dao_factory.plugins_configurations:insert {
            name = "filelog", value = { path = "/tmp/spec.log" }, api_id = api.id,
            consumer_id = untouched_consumer.id
          }
          assert.falsy(err)

          local results, err = dao_factory.plugins_configurations:find_by_keys {
            consumer_id = consumer.id
          }
          assert.falsy(err)
          assert.are.same(3, #results)
        end)

        teardown(function()
          spec_helper.drop_db()
        end)

        it("should delete all related plugins_configurations when deleting an API", function()
          local ok, err = dao_factory.consumers:delete(consumer)
          assert.True(ok)
          assert.falsy(err)

          local results, err = dao_factory.plugins_configurations:find_by_keys {
            consumer_id = consumer.id
          }
          assert.falsy(err)
          assert.are.same(0, #results)

          -- Make sure the untouched Consumer still has its plugin
          local results, err = dao_factory.plugins_configurations:find_by_keys {
            consumer_id = untouched_consumer.id
          }
          assert.falsy(err)
          assert.are.same(1, #results)
        end)

      end)
    end) -- describe :delete()

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
          assert.are.same(#entities, #results)
        end)

        it("should allow pagination", function()
          -- 1st page
          local rows_1, err = dao_factory[collection]:find(2)
          assert.falsy(err)
          assert.truthy(rows_1)
          assert.are.same(2, #rows_1)
          assert.truthy(rows_1.next_page)

          -- 2nd page
          local rows_2, err = dao_factory[collection]:find(2, rows_1.next_page)
          assert.falsy(err)
          assert.truthy(rows_2)
          assert.are.same(2, #rows_2)
        end)

      end)
    end) -- describe :find()

    describe(":find_one()", function()

      describe_core_collections(function(type, collection)

        it("should find one entity by id", function()
          local entities, err = session:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(entities)
          assert.True(#entities > 0)

          local result, err = dao_factory[collection]:find_one({ id = entities[1].id })
          assert.falsy(err)
          assert.truthy(result)
        end)

        it("should handle an invalid uuid value", function()
          local result, err = dao_factory[collection]:find_one({ id = "abcd" })
          assert.falsy(result)
          assert.True(err.invalid_type)
          assert.are.same("abcd is an invalid uuid", err.message.id)
        end)

      end)

      describe("plugin_configurations", function()

        setup(function()
          local fixtures = spec_helper.seed_db(1)
          faker:insert_from_table {
            plugin_configuration = {
              { name = "keyauth", value = {key_names = {"apikey"}}, api_id = fixtures.api[1].id }
            }
          }
        end)

        it("should deserialize the table property", function()
          local plugins_configurations, err = session:execute("SELECT * FROM plugins_configurations")
          assert.falsy(err)
          assert.truthy(plugins_configurations)
          assert.True(#plugins_configurations > 0)

          local plugin_t = plugins_configurations[1]

          local result, err = dao_factory.plugins_configurations:find_one({ id = plugin_t.id })
          assert.falsy(err)
          assert.truthy(result)
          assert.are.same("table", type(result.value))
        end)

      end)
    end) -- describe :find_one()

    describe(":find_by_keys()", function()

      describe_core_collections(function(type, collection)

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

        it("should query an entity by its queryable fields", function()
          local results, err = session:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(results)
          assert.True(#results > 0)

          local t = results[1]
          local q = {}

          -- Remove nonqueryable fields
          for k, schema_field in pairs(dao_factory[collection]._schema) do
            if schema_field.queryable then
              q[k] = t[k]
            elseif schema_field.type == "table" then
              t[k] = cjson.decode(t[k])
            end
          end

          local results, err = dao_factory[collection]:find_by_keys(q)
          assert.falsy(err)
          assert.truthy(results)

          -- in case of plugins configurations
          if t.consumer_id == constants.DATABASE_NULL_ID then
            t.consumer_id = nil
          end

          assert.are.same(t, results[1])
        end)

      end)
    end) -- describe :find_by_keys()

    --
    -- Plugins configuration additional behaviour
    --

    describe("plugin_configurations", function()
      local api_id
      local inserted_plugin

      it("should find distinct plugins configurations", function()
        faker:insert_from_table {
          api = {
            { name = "tests distinct 1", public_dns = "foo.com", target_url = "http://mockbin.com" },
            { name = "tests distinct 2", public_dns = "bar.com", target_url = "http://mockbin.com" }
          },
          plugin_configuration = {
            { name = "keyauth", value = {key_names = {"apikey"}, hide_credentials = true}, __api = 1 },
            { name = "ratelimiting", value = {period = "minute", limit = 6}, __api = 1 },
            { name = "ratelimiting", value = {period = "minute", limit = 6}, __api = 2 },
            { name = "filelog", value = { path = "/tmp/spec.log" }, __api = 1 }
          }
        }

        local res, err = dao_factory.plugins_configurations:find_distinct()

        assert.falsy(err)
        assert.truthy(res)

        assert.are.same(3, #res)
        assert.truthy(utils.table_contains(res, "keyauth"))
        assert.truthy(utils.table_contains(res, "ratelimiting"))
        assert.truthy(utils.table_contains(res, "filelog"))
      end)

      it("should insert a plugin and set the consumer_id to a 'null' uuid if none is specified", function()
        -- Since we want to specifically select plugins configurations which have _no_ consumer_id sometimes, we cannot rely on using
        -- NULL (and thus, not inserting the consumer_id column for the row). To fix this, we use a predefined, nullified uuid...

        -- Create an API
        local api_t = faker:fake_entity("api")
        local api, err = dao_factory.apis:insert(api_t)
        assert.falsy(err)

        local plugin_t = faker:fake_entity("plugin_configuration")
        plugin_t.api_id = api.id

        local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)
        assert.falsy(plugin.consumer_id)

        -- for next test
        api_id = api.id
        inserted_plugin = plugin
        inserted_plugin.consumer_id = nil
      end)

      it("should select a plugin configuration by 'null' uuid consumer_id and remove the column", function()
        -- Now we should be able to select this plugin
        local rows, err = dao_factory.plugins_configurations:find_by_keys {
          api_id = api_id,
          consumer_id = constants.DATABASE_NULL_ID
        }
        assert.falsy(err)
        assert.truthy(rows[1])
        assert.are.same(inserted_plugin, rows[1])
        assert.falsy(rows[1].consumer_id)
      end)

    end) -- describe plugins configurations
  end) -- describe DAO Collections

  --
  -- Keyauth plugin collection
  --

  -- describe("Keyauth", function()

  --   it("should not insert in DB if consumer does not exist", function()
  --     -- Without an consumer_id, it's a schema error
  --     local app_t = { name = "keyauth", value = {key_names = {"apikey"}} }
  --     local app, err = dao_factory.keyauth_credentials:insert(app_t)
  --     assert.falsy(app)
  --     assert.truthy(err)
  --     assert.is_daoError(err)
  --     assert.True(err.schema)
  --     assert.are.same("consumer_id is required", err.message.consumer_id)

  --     -- With an invalid consumer_id, it's a FOREIGN error
  --     local app_t = { key = "apikey123", consumer_id = uuid() }
  --     local app, err = dao_factory.keyauth_credentials:insert(app_t)
  --     assert.falsy(app)
  --     assert.truthy(err)
  --     assert.is_daoError(err)
  --     assert.True(err.foreign)
  --     assert.are.same("consumer_id "..app_t.consumer_id.." does not exist", err.message.consumer_id)
  --   end)

  --   it("should insert in DB and add generated values", function()
  --     local consumers, err = session:execute("SELECT * FROM consumers")
  --     assert.falsy(err)
  --     assert.truthy(#consumers > 0)

  --     local app_t = { key = "apikey123", consumer_id = consumers[1].id }
  --     local app, err = dao_factory.keyauth_credentials:insert(app_t)
  --     assert.falsy(err)
  --     assert.truthy(app.id)
  --     assert.truthy(app.created_at)
  --   end)

  --   it("should find an KeyAuth Credential by public_key", function()
  --     local app, err = dao_factory.keyauth_credentials:find_by_keys {
  --       key = "user122"
  --     }
  --     assert.falsy(err)
  --     assert.truthy(app)
  --   end)

  --   it("should handle empty strings", function()
  --     local apps, err = dao_factory.keyauth_credentials:find_by_keys {
  --       key = ""
  --     }
  --     assert.falsy(err)
  --     assert.are.same({}, apps)
  --   end)

  -- end)

  --
  -- Rate Limiting plugin collection
  --

  -- describe("Rate Limiting Metrics", function()
  --   local ratelimiting_metrics = dao_factory.ratelimiting_metrics
  --   local api_id = uuid()
  --   local identifier = uuid()

  --   after_each(function()
  --     spec_helper.drop_db()
  --   end)

  --   it("should return nil when ratelimiting metrics are not existing", function()
  --     local current_timestamp = 1424217600
  --     local periods = timestamp.get_timestamps(current_timestamp)
  --     -- Very first select should return nil
  --     for period, period_date in pairs(periods) do
  --       local metric, err = ratelimiting_metrics:find_one(api_id, identifier, current_timestamp, period)
  --       assert.falsy(err)
  --       assert.are.same(nil, metric)
  --     end
  --   end)

  --   it("should increment ratelimiting metrics with the given period", function()
  --     local current_timestamp = 1424217600
  --     local periods = timestamp.get_timestamps(current_timestamp)

  --     -- First increment
  --     local ok, err = ratelimiting_metrics:increment(api_id, identifier, current_timestamp)
  --     assert.falsy(err)
  --     assert.True(ok)

  --     -- First select
  --     for period, period_date in pairs(periods) do
  --       local metric, err = ratelimiting_metrics:find_one(api_id, identifier, current_timestamp, period)
  --       assert.falsy(err)
  --       assert.are.same({
  --         api_id = api_id,
  --         identifier = identifier,
  --         period = period,
  --         period_date = period_date,
  --         value = 1 -- The important part
  --       }, metric)
  --     end

  --     -- Second increment
  --     local ok, err = ratelimiting_metrics:increment(api_id, identifier, current_timestamp)
  --     assert.falsy(err)
  --     assert.True(ok)

  --     -- Second select
  --     for period, period_date in pairs(periods) do
  --       local metric, err = ratelimiting_metrics:find_one(api_id, identifier, current_timestamp, period)
  --       assert.falsy(err)
  --       assert.are.same({
  --         api_id = api_id,
  --         identifier = identifier,
  --         period = period,
  --         period_date = period_date,
  --         value = 2 -- The important part
  --       }, metric)
  --     end

  --     -- 1 second delay
  --     current_timestamp = 1424217601
  --     periods = timestamp.get_timestamps(current_timestamp)

  --      -- Third increment
  --     local ok, err = ratelimiting_metrics:increment(api_id, identifier, current_timestamp)
  --     assert.falsy(err)
  --     assert.True(ok)

  --     -- Third select with 1 second delay
  --     for period, period_date in pairs(periods) do

  --       local expected_value = 3

  --       if period == "second" then
  --         expected_value = 1
  --       end

  --       local metric, err = ratelimiting_metrics:find_one(api_id, identifier, current_timestamp, period)
  --       assert.falsy(err)
  --       assert.are.same({
  --         api_id = api_id,
  --         identifier = identifier,
  --         period = period,
  --         period_date = period_date,
  --         value = expected_value -- The important part
  --       }, metric)
  --     end
  --   end)

  --   it("should throw errors for non supported methods of the base_dao", function()
  --     assert.has_error(ratelimiting_metrics.find, "ratelimiting_metrics:find() not supported")
  --     assert.has_error(ratelimiting_metrics.insert, "ratelimiting_metrics:insert() not supported")
  --     assert.has_error(ratelimiting_metrics.update, "ratelimiting_metrics:update() not supported")
  --     assert.has_error(ratelimiting_metrics.delete, "ratelimiting_metrics:delete() not yet implemented")
  --     assert.has_error(ratelimiting_metrics.find_by_keys, "ratelimiting_metrics:find_by_keys() not supported")
  --   end)
  --
  --end) -- describe rate limiting metrics

end)
