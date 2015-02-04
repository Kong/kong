local configuration = require "spec.dao_configuration"
local CassandraFactory = require "apenode.dao.cassandra.factory"
local cjson = require "cjson"
local uuid = require "uuid"

local dao_factory = CassandraFactory(configuration.cassandra)

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

describe("Cassandra DAO", function()

  setup(function()
    dao_factory:migrate()
    dao_factory:prepare()
    dao_factory:seed()
  end)

  teardown(function()
    dao_factory:reset()
    dao_factory:close()
  end)

  describe("Cassandra DAO", function()

    describe(":insert()", function()

      describe("APIs", function()

        it("should insert in DB and add generated values", function()
          local api_t = dao_factory.faker.fake_entity("api")
          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(err)
          assert.truthy(api.id)
          assert.truthy(api.created_at)
        end)

        it("should not insert an invalid api", function()
          -- Nil
          local api, err = dao_factory.apis:insert()
          assert.falsy(api)
          assert.are.same("Cannot insert a nil element", err)

          -- Invalid type
          local api_t = dao_factory.faker.fake_entity("api", true)
          local api, err = dao_factory.apis:insert(api_t)
          assert.truthy(err)
          assert.falsy(api)

          -- Duplicated name
          local apis, err = dao_factory._db:execute("SELECT * FROM apis")
          assert.falsy(err)
          assert.truthy(#apis > 0)

          local api_t = dao_factory.faker.fake_entity("api")
          api_t.name = apis[1].name
          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(api)
          assert.truthy(err)
          assert.are.same("name already exists with value "..api_t.name, err.name)
        end)

      end)

      describe("Accounts", function()

        it("should insert an account in DB and add generated values", function()
          local account_t = dao_factory.faker.fake_entity("account")
          local account, err = dao_factory.accounts:insert(account_t)
          assert.falsy(err)
          assert.truthy(account.id)
          assert.truthy(account.created_at)
        end)

      end)

      describe("Applications", function()

        it("should not insert in DB if account does not exist", function()
          -- Without an account_id, it's a schema error
          local app_t = dao_factory.faker.fake_entity("application")
          local app, err = dao_factory.applications:insert(app_t)
          assert.falsy(app)
          assert.truthy(err)
          assert.are.same("account_id is required", err.account_id)

          -- With an invalid account_id, it's an EXISTS error
          local app_t = dao_factory.faker.fake_entity("application")
          app_t.account_id = uuid()

          local app, err = dao_factory.applications:insert(app_t)
          assert.falsy(app)
          assert.truthy(err)
          assert.are.same("account_id "..app_t.account_id.." does not exist", err.account_id)
        end)

        it("should insert in DB and add generated values", function()
          local accounts, err = dao_factory._db:execute("SELECT * FROM accounts")
          assert.falsy(err)
          assert.truthy(#accounts > 0)

          local app_t = dao_factory.faker.fake_entity("application")
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
          local plugin_t = dao_factory.faker.fake_entity("plugin")
          plugin_t.api_id = nil
          local plugin, err = dao_factory.plugins:insert(plugin_t)
          assert.falsy(plugin)
          assert.truthy(err)
          assert.are.same("api_id is required", err.api_id)

          -- With an invalid api_id, it's an EXISTS error
          local plugin_t = dao_factory.faker.fake_entity("plugin")
          plugin_t.api_id = uuid()

          local plugin, err = dao_factory.plugins:insert(plugin_t)
          assert.falsy(plugin)
          assert.truthy(err)
          assert.are.same("api_id "..plugin_t.api_id.." does not exist", err.api_id)

          -- With an invalid api_id application_id if specified, it's an EXISTS error
          local plugin_t = dao_factory.faker.fake_entity("plugin")
          plugin_t.api_id = uuid()
          plugin_t.application_id = uuid()

          local plugin, err = dao_factory.plugins:insert(plugin_t)
          assert.falsy(plugin)
          assert.truthy(err)
          assert.are.same("api_id "..plugin_t.api_id.." does not exist", err.api_id)
          assert.are.same("application_id "..plugin_t.application_id.." does not exist", err.application_id)
        end)

        it("should insert a plugin in DB and add generated values", function()
          -- Create an API and get an Application for insert
          local api_t = dao_factory.faker.fake_entity("api")
          local api, err = dao_factory.apis:insert(api_t)
          assert.falsy(err)

          local apps, err = dao_factory._db:execute("SELECT * FROM applications")
          assert.falsy(err)
          assert.True(#apps > 0)

          local plugin_t = dao_factory.faker.fake_entity("plugin")
          plugin_t.api_id = api.id
          plugin_t.application_id = apps[1].id

          local plugin, err = dao_factory.plugins:insert(plugin_t)
          assert.falsy(err)
          assert.truthy(plugin)
        end)

        it("should not insert twice a plugin with same api_id, application_id and name", function()
          -- Insert a new API for a fresh start
          local api, err = dao_factory.apis:insert(dao_factory.faker.fake_entity("api"))
          assert.falsy(err)
          assert.truthy(api.id)

          local apps, err = dao_factory._db:execute("SELECT * FROM applications")
          assert.falsy(err)
          assert.True(#apps > 0)

          local plugin_t = dao_factory.faker.fake_entity("plugin")
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
          assert.are.same("Plugin already exists", err)
        end)

      end)
    end)

    describe(":update()", function()

      describe_all_collections(function(type, collection)

        it("should not update in DB if entity cannot be found", function()
          local t = dao_factory.faker.fake_entity(type)
          t.id = uuid()

          -- No entity to update
          local entity, err = dao_factory[collection]:update(t)
          assert.falsy(entity)
          assert.truthy(err)
          assert.are.same("Entity to update not found", err)
        end)

      end)

      describe("APIs", function()

        -- Cassandra sets to NULL unset fields specified in an UPDATE query
        -- https://issues.apache.org/jira/browse/CASSANDRA-7304
        it("should update in DB without setting to NULL unset fields", function()
          local apis, err = dao_factory._db:execute("SELECT * FROM apis")
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

          local apis, err = dao_factory._db:execute("SELECT * FROM apis WHERE name = '"..api_t.name.."'")
          assert.falsy(err)
          assert.truthy(#apis == 1)
          assert.truthy(apis[1].id)
          assert.truthy(apis[1].created_at)
          assert.truthy(apis[1].public_dns)
          assert.truthy(apis[1].target_url)
          assert.are.same(api_t.name, apis[1].name)
        end)

        it("should prevent the update if the UNIQUE check fails", function()
          local apis, err = dao_factory._db:execute("SELECT * FROM apis")
          assert.falsy(err)
          assert.True(#apis > 0)

          local api_t = apis[1]
          api_t.name = api_t.name.." unique update attempt"

          -- Should not work because UNIQUE check fails
          api_t.public_dns = apis[2].public_dns

          local api, err = dao_factory.apis:update(api_t)
          assert.falsy(api)
          assert.truthy(err)
          assert.are.same("public_dns already exists with value "..api_t.public_dns, err.public_dns)
        end)

      end)

      describe("Accounts", function()

        it("should update in DB if entity can be found", function()
          local accounts, err = dao_factory._db:execute("SELECT * FROM accounts")
          assert.falsy(err)
          assert.True(#accounts > 0)

          local account_t = accounts[1]

          -- Should be correctly updated in DB
          account_t.provider_id = account_t.provider_id.."updated"

          local account, err = dao_factory.accounts:update(account_t)
          assert.falsy(err)
          assert.truthy(account)

          local accounts, err = dao_factory._db:execute("SELECT * FROM accounts WHERE provider_id = '"..account_t.provider_id.."'")
          assert.falsy(err)
          assert.True(#accounts == 1)
          assert.are.same(account_t.name, accounts[1].name)
        end)

      end)

      describe("Applications", function()

        it("should update in DB if entity can be found", function()
          local apps, err = dao_factory._db:execute("SELECT * FROM applications")
          assert.falsy(err)
          assert.True(#apps > 0)

          local app_t = apps[1]
          app_t.public_key = "updated public_key"
          local app, err = dao_factory.applications:update(app_t)
          assert.falsy(err)
          assert.truthy(app)
        end)

      end)
    end)

    describe(":delete()", function()

      describe_all_collections(function(type, collection)

        it("should return an error if deleting an entity that cannot be found", function()
          local t = dao_factory.faker.fake_entity(type)
          t.id = uuid()

          local success, err = dao_factory[collection]:delete(t.id)
          assert.is_not_true(success)
          assert.truthy(err)
          assert.are.same("Entity to delete not found", err)
        end)

        it("should delete an entity if it can be found", function()
          local entities, err = dao_factory._db:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(entities)
          assert.True(#entities > 0)

          local success, err = dao_factory[collection]:delete(entities[1].id)
          assert.falsy(err)
          assert.True(success)

          local entities, err = dao_factory._db:execute("SELECT * FROM "..collection.." WHERE id = "..entities[1].id )
          assert.falsy(err)
          assert.truthy(entities)
          assert.True(#entities == 0)
        end)

      end)
    end)

    describe(":find()", function()

      describe_all_collections(function(type, collection)

        it("should find entities", function()
          local entities, err = dao_factory._db:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(entities)
          assert.True(#entities > 0)

          local results, err = dao_factory[collection]:find()
          assert.falsy(err)
          assert.truthy(results)
          assert.True(#entities == #results)
        end)

      end)
    end)

    describe(":find_one()", function()

      describe_all_collections(function(type, collection)

        it("should find one entity by id", function()
          local entities, err = dao_factory._db:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(entities)
          assert.True(#entities > 0)

          local results, err = dao_factory[collection]:find_one(entities[1].id)
          assert.falsy(err)
          assert.truthy(results)
          assert.True(#results == 1)
        end)

      end)

      describe("Plugins", function()

        it("should deserialize the table property", function()
          local plugins, err = dao_factory._db:execute("SELECT * FROM plugins")
          assert.falsy(err)
          assert.truthy(plugins)
          assert.True(#plugins > 0)

          local plugin_t = plugins[1]

          local results, err = dao_factory.plugins:find_one(plugin_t.id)
          assert.falsy(err)
          assert.truthy(results)
          assert.True(type(results[1].value) == "table")
        end)

      end)
    end)

    describe(":find_by_keys()", function()

      describe_all_collections(function(type, collection)

        it("should refuse non queryable keys", function()
          local results, err = dao_factory._db:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(results)
          assert.True(#results > 0)

          local t = results[1]

          local results, err = dao_factory[collection]:find_by_keys(t)
          assert.truthy(err)
          assert.falsy(results)

          -- All those fields are indeed non queryable
          for k,v in pairs(err) do
            assert.is_not_true(dao_factory[collection]._schema[k].queryable)
          end
        end)

        it("should query an entity by its queryable fields", function()
          local results, err = dao_factory._db:execute("SELECT * FROM "..collection)
          assert.falsy(err)
          assert.truthy(results)
          assert.True(#results > 0)

          local t = results[1]
          local q = {}

          -- Remove nonqueryable fields
          for k,schema_field in pairs(dao_factory[collection]._schema) do
            if schema_field.queryable then
              q[k] = t[k]
            elseif schema_field.type == "table" then
              t[k] = cjson.decode(t[k])
            end
          end

          local results, err = dao_factory[collection]:find_by_keys(q)
          assert.falsy(err)
          assert.truthy(results)
          assert.are.same(t, results[1])
        end)

      end)
    end)
  end)
end)
