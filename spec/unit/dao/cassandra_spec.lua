local configuration = require "spec.dao_configuration"
local CassandraFactory = require "apenode.dao.cassandra.factory"

local dao_factory = CassandraFactory(configuration.cassandra)

describe("BaseDao", function()

  setup(function()
    dao_factory:prepare()
    dao_factory:seed()
  end)

  teardown(function()
    --dao_factory:drop()
    --dao_factory:close()
  end)

  describe("Cassandra DAO", function()

    describe(":save()", function()

      describe("APIs", function()

        it("should insert in db and add generated values", function()
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
          assert.are.same("Unique check failed on field: name with value: "..api_t.name, err)
        end)

      end)

      describe("Accounts", function()

        it("should insert an account in db and add generated values", function()
          local account_t = dao_factory.faker.fake_entity("account")
          local account, err = dao_factory.accounts:insert(account_t)
          assert.falsy(err)
          assert.truthy(account.id)
          assert.truthy(account.created_at)
        end)

      end)

      describe("Applications", function()

        it("should not insert in db if account does not exist", function()
          -- Without an account_id, it's a schema error
          local app_t = dao_factory.faker.fake_entity("application")
          local app, err = dao_factory.applications:insert(app_t)
          assert.falsy(app)
          assert.are.same("account_id is required", err.account_id)

          -- With an invalid account_id, it's an EXISTS error
          local uuid = require "uuid"

          local app_t = dao_factory.faker.fake_entity("application")
          app_t.account_id = uuid()

          local app, err = dao_factory.applications:insert(app_t)
          assert.falsy(app)
          assert.are.same("Exists check failed on field: account_id with value: "..app_t.account_id, err)
        end)

        it("should insert in db and add generated values", function()
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
    end)
  end)
end)
