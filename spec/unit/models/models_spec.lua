local Faker = require "apenode.tools.faker"
local Api = require "apenode.models.api"

describe("Models", function()

  describe("Api", function()

    describe("#new()", function()

      it("should create a model with required properties", function()
        local values = Faker.fake_entity("api")
        local api = Api(values, { apis = {} })

        assert.truthy(api._dao)
        assert.truthy(api._schema)
        assert.are.same(values, api._t)
      end)

    end)

    describe("Persistance", function()
      local SQLiteFactory = require "apenode.dao.sqlite.factory"
      local dao = SQLiteFactory({ memory = false, file_path = "/tmp/apenode.sqlite3" })

      teardown(function()
        --dao:drop()
      end)

      describe("#save()", function()

        it("should validate the values before saving", function()
          local values = Faker.fake_entity("api", true)
          local api = Api(values, {})

          local res_values, err = api:save()
          assert.falsy(res_values)
          assert.truthy(err.name)
        end)

        it("should save a model's values", function()
          local values = Faker.fake_entity("api")
          local api = Api(values, dao)

          local res_values, err = api:save()
          assert.falsy(err)
          assert.truthy(res_values.id)
        end)

        it("should respect the unique constraint on a schema", function()
          -- Success
          local values = { name = "mashape", public_dns = "httpbin.org", target_url = "http://httpbin.org" }
          local api = Api(values, dao)

          local res_values, err = api:save()
          assert.falsy(err)

          -- Error, name already exists
          local values = { name = "mashape", public_dns = "httpbin2.org", target_url = "http://httpbin.org" }
          local api_clone = Api(values, dao)

          local res_values, err = api_clone:save()
          assert.falsy(res_values)
          assert.are.same("name with value \"mashape\" already exists", err)
        end)

      end)

      describe("#update()", function()

        it("should validate the values before updating", function()
          local values = Faker.fake_entity("api", true)
          local api = Api(values, {})

          local res_values, err = api:update()
          assert.falsy(res_values)
          assert.truthy(err.name)
        end)

        it("should update a model in the DB", function()
          local values = Faker.fake_entity("api")
          local api = Api(values, dao)

          local res_values, err = api:save()
          assert.falsy(err)

          -- Update
          api.name = "new name"
          local res_values, err = api:update()
          assert.falsy(err)
          assert.are.same("new name", res_values.name)
        end)

      end)
    end)
  end)
end)
