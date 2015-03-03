-- dependencies
local cassandra = require "cassandra"
local constants = require "kong.constants"
local cjson = require "cjson"
local uuid = require "uuid"

-- Kong modules
local Faker = require "kong.tools.faker"
local Migrations = require "kong.tools.migrations"
local configuration = require "spec.dao_configuration"
local CassandraFactory = require "kong.dao.cassandra.factory"

-- Start instances
local dao_factory = CassandraFactory(configuration.cassandra)
local migrations = Migrations(dao_factory)
local faker = Faker(dao_factory)

-- An utility function to apply tests on each collection
local function describe_all_collections(tests_cb)
  for type, dao in pairs({ api = dao_factory.apis,
                           account = dao_factory.accounts,
                           application = dao_factory.applications,
                           plugin = dao_factory.plugins }) do
    local collection = type.."s"
    describe(collection, function()
      tests_cb(type, collection)
    end)
  end
end

-- Let's go
describe("Cassandra DAO #dao #cassandra", function()

  setup(function()
    -- Migrate our schema
    migrations:migrate(function(_, err)
      assert.falsy(err)
    end)

    -- Prepare dao statements
    local err = dao_factory:prepare()
    if err then
      error(err)
    end
    -- Seed DB with dummy entities
    faker:seed()

    -- Create a session to verify the dao's behaviour
    session = cassandra.new()
    session:set_timeout(configuration.cassandra.timeout)

    local connected, err = session:connect(configuration.cassandra.hosts, configuration.cassandra.port)
    assert.falsy(err)

    local ok, err = session:set_keyspace(configuration.cassandra.keyspace)
    assert.falsy(err)
  end)

  teardown(function()
    if session then
      session:close()
    end
    migrations:reset(function(_, err)
      assert.falsy(err)
    end)
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
      assert.are.same("connection refused", err)
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
        assert.True(err.unique)
        assert.are.same("name already exists with value "..api_t.name, err.message.name)
      end)

    end)

    describe("Accounts", function()

      it("should insert an account in DB and add generated values", function()
        local account_t = faker:fake_entity("account")
        local account, err = dao_factory.accounts:insert(account_t)
        assert.falsy(err)
        assert.truthy(account.id)
        assert.truthy(account.created_at)
      end)

    end)

    describe("Applications", function()

      it("should not insert in DB if account does not exist", function()
        -- Without an account_id, it's a schema error
        local app_t = faker:fake_entity("application")
        app_t.account_id = nil
        local app, err = dao_factory.applications:insert(app_t)
        assert.falsy(app)
        assert.truthy(err)
        assert.True(err.schema)
        assert.are.same("account_id is required", err.message.account_id)

        -- With an invalid account_id, it's a FOREIGN error
        local app_t = faker:fake_entity("application")
        app_t.account_id = uuid()

        local app, err = dao_factory.applications:insert(app_t)
        assert.falsy(app)
        assert.truthy(err)
        assert.True(err.foreign)
        assert.are.same("account_id "..app_t.account_id.." does not exist", err.message.account_id)
      end)

      it("should insert in DB and add generated values", function()
        local accounts, err = session:execute("SELECT * FROM accounts")
        assert.falsy(err)
        assert.truthy(#accounts > 0)

        local app_t = faker:fake_entity("application")
        app_t.account_id = accounts[1].id

        local app, err = dao_factory.applications:insert(app_t)
        assert.falsy(err)
        assert.truthy(app.id)
        assert.truthy(app.created_at)
      end)

    end)

    describe("Plugins", function()

      it("should not insert in DB if invalid", function()
        -- Without an api_id, it's a schema error
        local plugin_t = faker:fake_entity("plugin")
        plugin_t.api_id = nil
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.schema)
        assert.are.same("api_id is required", err.message.api_id)

        -- With an invalid api_id, it's an FOREIGN error
        local plugin_t = faker:fake_entity("plugin")
        plugin_t.api_id = uuid()

        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.foreign)
        assert.are.same("api_id "..plugin_t.api_id.." does not exist", err.message.api_id)

        -- With invalid api_id and application_id, it's an EXISTS error
        local plugin_t = faker:fake_entity("plugin")
        plugin_t.api_id = uuid()
        plugin_t.application_id = uuid()

        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.foreign)
        assert.are.same("api_id "..plugin_t.api_id.." does not exist", err.message.api_id)
        assert.are.same("application_id "..plugin_t.application_id.." does not exist", err.message.application_id)
      end)

      it("should insert a plugin in DB and add generated values", function()
        -- Create an API and get an Application for insert
        local api_t = faker:fake_entity("api")
        local api, err = dao_factory.apis:insert(api_t)
        assert.falsy(err)

        local apps, err = session:execute("SELECT * FROM applications")
        assert.falsy(err)
        assert.True(#apps > 0)

        local plugin_t = faker:fake_entity("plugin")
        plugin_t.api_id = api.id
        plugin_t.application_id = apps[1].id

        local plugin, err = dao_factory.plugins:insert(plugin_t)
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

        local plugin_t = faker:fake_entity("plugin")
        plugin_t.api_id = api.id
        plugin_t.application_id = apps[#apps].id

        -- This should work
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)

        -- This should fail
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
        assert.True(err.unique)
        assert.are.same("Plugin already exists", err.message)
      end)

      it("should not insert a plugin if this plugin doesn't exist (not installed)", function()
        local plugin_t = faker:fake_entity("plugin")
        plugin_t.name = "world domination plugin"

        -- This should fail
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(plugin)
        assert.truthy(err)
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
          name = "authentication",
          value = {
            authentication_type = "query",
            authentication_key_names = { "x-kong-key" }
          }
        }

        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)

        local ok, err = dao_factory.plugins:delete(plugin.id)
        assert.True(ok)
        assert.falsy(err)

        -- Failure
        plugin_t.value.authentication_type = "hello"
        local plugin, err = dao_factory.plugins:insert(plugin_t)
        assert.truthy(err)
        assert.truthy(err.schema)
        assert.are.same("\"hello\" is not allowed. Allowed values are: \"query\", \"basic\", \"header\"", err.message["value.authentication_type"])
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
        assert.True(err.unique)
        assert.are.same("public_dns already exists with value "..api_t.public_dns, err.message.public_dns)
      end)

    end)

    describe("Accounts", function()

      it("should update in DB if entity can be found", function()
        local accounts, err = session:execute("SELECT * FROM accounts")
        assert.falsy(err)
        assert.True(#accounts > 0)

        local account_t = accounts[1]

        -- Should be correctly updated in DB
        account_t.provider_id = account_t.provider_id.."updated"

        local account, err = dao_factory.accounts:update(account_t)
        assert.falsy(err)
        assert.truthy(account)

        local accounts, err = session:execute("SELECT * FROM accounts WHERE provider_id = '"..account_t.provider_id.."'")
        assert.falsy(err)
        assert.True(#accounts == 1)
        assert.are.same(account_t.name, accounts[1].name)
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

    describe("Plugins", function()

      it("should update in DB if entity can be found", function()
        local plugins, err = session:execute("SELECT * FROM plugins")
        assert.falsy(err)
        assert.True(#plugins > 0)

        local plugin_t = plugins[1]
        plugin_t.value = cjson.decode(plugin_t.value)
        plugin_t.enabled = false
        local plugin, err = dao_factory.plugins:update(plugin_t)
        assert.falsy(err)
        assert.truthy(plugin)

        local plugins, err = session:execute("SELECT * FROM plugins WHERE id = ?", { cassandra.uuid(plugin_t.id) })
        assert.falsy(err)
        assert.are.same(1, #plugins)
      end)

    end)
  end)

  describe(":delete()", function()

    setup(function()
      dao_factory:drop()
      faker:seed()
    end)

    teardown(function()
      dao_factory:drop()
      faker:seed()
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
      dao_factory:drop()
faker:seed(true, 100)
    end)

    teardown(function()
      dao_factory:drop()
faker:seed()
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

    describe("Plugins", function()

      it("should deserialize the table property", function()
        local plugins, err = session:execute("SELECT * FROM plugins")
        assert.falsy(err)
        assert.truthy(plugins)
        assert.True(#plugins > 0)

        local plugin_t = plugins[1]

        local result, err = dao_factory.plugins:find_one(plugin_t.id)
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

        -- in case of plugins
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
    local utils = require "kong.tools.utils"
    local metrics = dao_factory.metrics

    local api_id = uuid()
    local identifier = uuid()

    after_each(function()
      dao_factory:drop()
    end)

    it("should return nil when metrics are not existing", function()
      local current_timestamp = 1424217600
      local periods = utils.get_timestamps(current_timestamp)
      -- Very first select should return nil
      for period, period_date in pairs(periods) do
        local metric, err = metrics:find_one(api_id, identifier, current_timestamp, period)
        assert.falsy(err)
        assert.are.same(nil, metric)
      end
    end)

    it("should increment metrics with the given period", function()
      local current_timestamp = 1424217600
      local periods = utils.get_timestamps(current_timestamp)

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
      periods = utils.get_timestamps(current_timestamp)

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
  end)

  describe("Plugins", function()
    local api_id
    local inserted_plugin

    it("should insert a plugin and set the application_id to a 'null' uuid if none is specified", function()
      -- Since we want to specifically select plugins which have _no_ application_id sometimes, we cannot rely on using
      -- NULL (and thus, not inserting the application_id column for the row). To fix this, we use a predefined, nullified
      -- uuid...

      -- Create an API
      local api_t = faker:fake_entity("api")
      local api, err = dao_factory.apis:insert(api_t)
      assert.falsy(err)

      local plugin_t = faker:fake_entity("plugin")
      plugin_t.api_id = api.id
      plugin_t.application_id = nil

      local plugin, err = dao_factory.plugins:insert(plugin_t)
      assert.falsy(err)
      assert.truthy(plugin)
      assert.falsy(plugin.application_id)

      -- for next test
      api_id = api.id
      inserted_plugin = plugin
      inserted_plugin.application_id = nil
    end)

    it("should select a plugin by 'null' uuid application_id and remove the column", function()
      -- Now we should be able to select this plugin
      local rows, err = dao_factory.plugins:find_by_keys {
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