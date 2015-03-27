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
local env = spec_helper.get_env()
local faker = env.faker
local dao_factory = env.dao_factory
local configuration = env.configuration
configuration.cassandra = configuration.databases_available[configuration.database].properties

-- An utility function to apply tests on each collection
local function describe_all_collections(tests_cb)
  for type, dao in pairs({ api = dao_factory.apis,
                           consumer = dao_factory.consumers,
                           application = dao_factory.applications,
                           plugin_configuration = dao_factory.plugins_configurations }) do

    local collection = type=="plugin_configuration" and "plugins_configurations" or type.."s"
    describe(collection, function()
      tests_cb(type, collection)
    end)
  end
end

local function daoError(state, arguments)
  local stub_err = DaoError("", "")
  return getmetatable(stub_err) == getmetatable(arguments[1])
end

local say = require("say")
say:set("assertion.daoError.positive", "Expected %s\nto be a DaoError")
say:set("assertion.daoError.negative", "Expected %s\nto not be a DaoError")
assert:register("assertion", "daoError", daoError, "assertion.daoError.positive", "assertion.daoError.negative")

-- Let's go
describe("Cassandra DAO #dao #cassandra", function()

  setup(function()
    spec_helper.prepare_db()

    -- Create a session to verify the dao's behaviour
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
    spec_helper.reset_db()
  end)

  describe("Factory", function()

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
      assert.are.same("connection refused", err.message)
    end)

  end)

  describe("Schemas", function()

    describe_all_collections(function(type, collection)

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

  describe(":insert()", function()

    describe("APIs", function()

      it("should insert in DB and add generated values", function()
        local api_t = faker:fake_entity("api")
        local api, err = dao_factory.apis:insert(api_t)
        assert.falsy(err)
        assert.truthy(api.id)
        assert.truthy(api.created_at)
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
        assert.are.same("name already exists with value "..api_t.name, err.message.name)
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
        assert.are.same("name already exists with value "..api_t.name, err.message.name)
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

    describe("Applications", function()

      it("should not insert in DB if consumer does not exist", function()
        -- Without an consumer_id, it's a schema error
        local app_t = faker:fake_entity("application")
        app_t.consumer_id = nil
        local app, err = dao_factory.applications:insert(app_t)
        assert.falsy(app)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.schema)
        assert.are.same("consumer_id is required", err.message.consumer_id)

        -- With an invalid consumer_id, it's a FOREIGN error
        local app_t = faker:fake_entity("application")
        app_t.consumer_id = uuid()

        local app, err = dao_factory.applications:insert(app_t)
        assert.falsy(app)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.foreign)
        assert.are.same("consumer_id "..app_t.consumer_id.." does not exist", err.message.consumer_id)
      end)

      it("should insert in DB and add generated values", function()
        local consumers, err = session:execute("SELECT * FROM consumers")
        assert.falsy(err)
        assert.truthy(#consumers > 0)

        local app_t = faker:fake_entity("application")
        app_t.consumer_id = consumers[1].id

        local app, err = dao_factory.applications:insert(app_t)
        assert.falsy(err)
        assert.truthy(app.id)
        assert.truthy(app.created_at)
      end)

    end)

    describe("Plugin Configurations", function()

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

        -- With invalid api_id and application_id, it's an EXISTS error
        local plugin_t = faker:fake_entity("plugin_configuration")
        plugin_t.api_id = uuid()
        plugin_t.application_id = uuid()

        local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.foreign)
        assert.are.same("api_id "..plugin_t.api_id.." does not exist", err.message.api_id)
        assert.are.same("application_id "..plugin_t.application_id.." does not exist", err.message.application_id)
      end)

      it("should insert a plugin configuration in DB and add generated values", function()
        -- Create an API and get an Application for insert
        local api_t = faker:fake_entity("api")
        local api, err = dao_factory.apis:insert(api_t)
        assert.falsy(err)

        local apps, err = session:execute("SELECT * FROM applications")
        assert.falsy(err)
        assert.True(#apps > 0)

        local plugin_t = faker:fake_entity("plugin_configuration")
        plugin_t.api_id = api.id
        plugin_t.application_id = apps[1].id

        local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)
        assert.truthy(plugin.application_id)
      end)

      it("should not insert twice a plugin with same api_id, application_id and name", function()
        -- Insert a new API for a fresh start
        local api, err = dao_factory.apis:insert(faker:fake_entity("api"))
        assert.falsy(err)
        assert.truthy(api.id)

        local apps, err = session:execute("SELECT * FROM applications")
        assert.falsy(err)
        assert.True(#apps > 0)

        local plugin_t = faker:fake_entity("plugin_configuration")
        plugin_t.api_id = api.id
        plugin_t.application_id = apps[#apps].id

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
        assert.are.same("Plugin already exists", err.message)
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

        local apps, err = session:execute("SELECT * FROM applications")
        assert.falsy(err)
        assert.True(#apps > 0)

        local plugin_t =  {
          api_id = api.id,
          application_id = apps[#apps].id,
          name = "queryauth",
          value = {
            key_names = { "x-kong-key" }
          }
        }

        local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)

        local ok, err = dao_factory.plugins_configurations:delete(plugin.id)
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
  end)

  describe(":update()", function()

    describe_all_collections(function(type, collection)

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
        assert.are.same("public_dns already exists with value "..api_t.public_dns, err.message.public_dns)
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

    describe("Applications", function()

      it("should update in DB if entity can be found", function()
        local apps, err = session:execute("SELECT * FROM applications")
        assert.falsy(err)
        assert.True(#apps > 0)

        local app_t = apps[1]
        app_t.public_key = "updated public_key"
        local app, err = dao_factory.applications:update(app_t)
        assert.falsy(err)
        assert.truthy(app)

        local apps, err = session:execute("SELECT * FROM applications WHERE public_key = ?", { app_t.public_key })
        assert.falsy(err)
        assert.are.same(1, #apps)
      end)

    end)

    describe("Plugin Configurations", function()

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
  end)

  describe(":delete()", function()

    setup(function()
      spec_helper.drop_db()
      spec_helper.seed_db(nil, 100)
    end)

    describe_all_collections(function(type, collection)

      it("should return false if there was nothing to delete", function()
        local ok, err = dao_factory[collection]:delete(uuid())
        assert.is_not_true(ok)
        assert.falsy(err)
      end)

      it("should delete an entity if it can be found", function()
        local entities, err = session:execute("SELECT * FROM "..collection)
        assert.falsy(err)
        assert.truthy(entities)
        assert.True(#entities > 0)

        local success, err = dao_factory[collection]:delete(entities[1].id)
        assert.falsy(err)
        assert.True(success)

        local entities, err = session:execute("SELECT * FROM "..collection.." WHERE id = "..entities[1].id )
        assert.falsy(err)
        assert.truthy(entities)
        assert.are.same(0, #entities)
      end)

    end)
  end)

  describe(":find()", function()

    setup(function()
      spec_helper.drop_db()
      spec_helper.seed_db(nil, 100)
    end)

    describe_all_collections(function(type, collection)

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
  end)

  describe(":find_one()", function()

    describe_all_collections(function(type, collection)

      it("should find one entity by id", function()
        local entities, err = session:execute("SELECT * FROM "..collection)
        assert.falsy(err)
        assert.truthy(entities)
        assert.True(#entities > 0)

        local result, err = dao_factory[collection]:find_one(entities[1].id)
        assert.falsy(err)
        assert.truthy(result)
      end)

      it("should handle an invalid uuid value", function()
        local result, err = dao_factory[collection]:find_one("abcd")
        assert.falsy(result)
        assert.True(err.invalid_type)
        assert.are.same("abcd is an invalid uuid", err.message.id)
      end)

    end)

    describe("Plugin Configurations", function()

      it("should deserialize the table property", function()
        local plugins_configurations, err = session:execute("SELECT * FROM plugins_configurations")
        assert.falsy(err)
        assert.truthy(plugins_configurations)
        assert.True(#plugins_configurations > 0)

        local plugin_t = plugins_configurations[1]

        local result, err = dao_factory.plugins_configurations:find_one(plugin_t.id)
        assert.falsy(err)
        assert.truthy(result)
        assert.are.same("table", type(result.value))
      end)

    end)
  end)

  describe(":find_by_keys()", function()

    describe_all_collections(function(type, collection)

      it("should refuse non queryable keys", function()
        local results, err = session:execute("SELECT * FROM "..collection)
        assert.falsy(err)
        assert.truthy(results)
        assert.True(#results > 0)

        local t = results[1]

        local results, err = dao_factory[collection]:find_by_keys(t)
        assert.truthy(err)
        assert.is_daoError(err)
        assert.True(err.schema)
        assert.falsy(results)

        -- All those fields are indeed non queryable
        for k,v in pairs(err.message) do
          assert.is_not_true(dao_factory[collection]._schema[k].queryable)
        end
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
        if t.application_id == constants.DATABASE_NULL_ID then
          t.application_id = nil
        end

        assert.are.same(t, results[1])
      end)

    end)

    describe("Applications", function()

      it("should find an application by public_key", function()
        local app, err = dao_factory.applications:find_by_keys {
          public_key = "user122"
        }
        assert.falsy(err)
        assert.truthy(app)
      end)

      it("should handle empty strings", function()
        local apps, err = dao_factory.applications:find_by_keys {
          public_key = ""
        }
        assert.falsy(err)
        assert.are.same({}, apps)
      end)

    end)

  end)

  describe("Metrics", function()
    local metrics = dao_factory.metrics

    local api_id = uuid()
    local identifier = uuid()

    after_each(function()
      spec_helper.drop_db()
    end)

    it("should return nil when metrics are not existing", function()
      local current_timestamp = 1424217600
      local periods = timestamp.get_timestamps(current_timestamp)
      -- Very first select should return nil
      for period, period_date in pairs(periods) do
        local metric, err = metrics:find_one(api_id, identifier, current_timestamp, period)
        assert.falsy(err)
        assert.are.same(nil, metric)
      end
    end)

    it("should increment metrics with the given period", function()
      local current_timestamp = 1424217600
      local periods = timestamp.get_timestamps(current_timestamp)

      -- First increment
      local ok, err = metrics:increment(api_id, identifier, current_timestamp)
      assert.falsy(err)
      assert.True(ok)

      -- First select
      for period, period_date in pairs(periods) do
        local metric, err = metrics:find_one(api_id, identifier, current_timestamp, period)
        assert.falsy(err)
        assert.are.same({
          api_id = api_id,
          identifier = identifier,
          period = period,
          period_date = period_date,
          value = 1 -- The important part
        }, metric)
      end

      -- Second increment
      local ok, err = metrics:increment(api_id, identifier, current_timestamp)
      assert.falsy(err)
      assert.True(ok)

      -- Second select
      for period, period_date in pairs(periods) do
        local metric, err = metrics:find_one(api_id, identifier, current_timestamp, period)
        assert.falsy(err)
        assert.are.same({
          api_id = api_id,
          identifier = identifier,
          period = period,
          period_date = period_date,
          value = 2 -- The important part
        }, metric)
      end

      -- 1 second delay
      current_timestamp = 1424217601
      periods = timestamp.get_timestamps(current_timestamp)

       -- Third increment
      local ok, err = metrics:increment(api_id, identifier, current_timestamp)
      assert.falsy(err)
      assert.True(ok)

      -- Third select with 1 second delay
      for period, period_date in pairs(periods) do

        local expected_value = 3

        if period == "second" then
          expected_value = 1
        end

        local metric, err = metrics:find_one(api_id, identifier, current_timestamp, period)
        assert.falsy(err)
        assert.are.same({
          api_id = api_id,
          identifier = identifier,
          period = period,
          period_date = period_date,
          value = expected_value -- The important part
        }, metric)
      end
    end)

    it("should throw errors for non supported methods of the base_dao", function()
      assert.has_error(metrics.find, "metrics:find() not supported")
      assert.has_error(metrics.insert, "metrics:insert() not supported")
      assert.has_error(metrics.update, "metrics:update() not supported")
      assert.has_error(metrics.delete, "metrics:delete() not yet implemented")
      assert.has_error(metrics.find_by_keys, "metrics:find_by_keys() not supported")
    end)

  end)

  describe("Plugin Configurations", function()
    local api_id
    local inserted_plugin

    setup(function()
      spec_helper.drop_db()
      spec_helper.seed_db(nil, 100)
    end)

    it("should find distinct plugins configurations", function()
      local res, err = dao_factory.plugins_configurations:find_distinct()

      assert.falsy(err)
      assert.truthy(res)

      assert.are.same(7, #res)
      assert.truthy(utils.array_contains(res, "queryauth"))
      assert.truthy(utils.array_contains(res, "headerauth"))
      assert.truthy(utils.array_contains(res, "basicauth"))
      assert.truthy(utils.array_contains(res, "ratelimiting"))
      assert.truthy(utils.array_contains(res, "tcplog"))
      assert.truthy(utils.array_contains(res, "udplog"))
      assert.truthy(utils.array_contains(res, "filelog"))
    end)

    it("should insert a plugin and set the application_id to a 'null' uuid if none is specified", function()
      -- Since we want to specifically select plugins configurations which have _no_ application_id sometimes, we cannot rely on using
      -- NULL (and thus, not inserting the application_id column for the row). To fix this, we use a predefined, nullified
      -- uuid...

      -- Create an API
      local api_t = faker:fake_entity("api")
      local api, err = dao_factory.apis:insert(api_t)
      assert.falsy(err)

      local plugin_t = faker:fake_entity("plugin_configuration")
      plugin_t.api_id = api.id

      local plugin, err = dao_factory.plugins_configurations:insert(plugin_t)
      assert.falsy(err)
      assert.truthy(plugin)
      assert.falsy(plugin.application_id)

      -- for next test
      api_id = api.id
      inserted_plugin = plugin
      inserted_plugin.application_id = nil
    end)

    it("should select a plugin configuration by 'null' uuid application_id and remove the column", function()
      -- Now we should be able to select this plugin
      local rows, err = dao_factory.plugins_configurations:find_by_keys {
        api_id = api_id,
        application_id = constants.DATABASE_NULL_ID
      }
      assert.falsy(err)
      assert.truthy(rows[1])
      assert.are.same(inserted_plugin, rows[1])
      assert.falsy(rows[1].application_id)
    end)

  end)
end)
