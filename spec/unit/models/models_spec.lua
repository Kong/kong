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

      local dao_configuration = require "spec.unit.dao_configuration"

      -- Let's test with each DAO
      for dao_type, properties in pairs(dao_configuration) do
        local Factory = require("apenode.dao."..dao_type..".factory")
        local dao = Factory(properties)

        describe(dao_type, function()
          describe("#save()", function()

            setup(function()
              dao:drop()
            end)

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

            setup(function()
              dao:drop()
            end)

            it("should validate the values before updating", function()
              local values = Faker.fake_entity("api", true)
              local api = Api(values, dao)

              local row_count, err = api:update()
              assert.truthy(err)
              assert.equal(0, row_count)
            end)

            it("should update a model in the DB", function()
              local values = Faker.fake_entity("api")
              local api = Api(values, dao)

              local res_values, err = api:save()
              assert.falsy(err)

              -- Update
              api.name = "new name"
              local row_count, err = api:update()
              assert.falsy(err)
              assert.equal(1, row_count)
            end)

            it("should respect the unique constraint on a schema", function()
              local values_1 = Faker.fake_entity("api")
              values_1.name = "unique name"
              local api_1 = Api(values_1, dao)

              local values_2 = Faker.fake_entity("api")
              local api_2 = Api(values_2, dao)

              -- Save API 1
              local res_values, err = api_1:save()
              assert.falsy(err)

              -- Save API 2
              local res_values, err = api_2:save()
              assert.falsy(err)

              -- Should fail
              api_2.name = "unique name"
              local row_count, err = api_2:update()
              assert.truthy(err)
              assert.are.same("name with value \"unique name\" already exists", err)
            end)

          end)

          describe("#delete()", function()

            setup(function()
              dao:drop()
            end)

            it("should delete a model from the database", function()
              local values = Faker.fake_entity("api")
              local api = Api(values, dao)

              local res_values, err = api:save()
              assert.falsy(err)

              -- Delete
              local success, err = api:delete()
              assert.falsy(err)
              assert.truthy(success)
            end)

            it("should return false if a model cannot be found", function()
              local uuid = require "uuid"
              local values = Faker.fake_entity("api")
              local api = Api(values, dao)

              local res_values, err = api:save()
              assert.falsy(err)

              -- Fail Delete
              api._t.id = uuid()
              local success, err = api:delete()
              assert.falsy(err)
              assert.falsy(success)
            end)

            it("should return an error if trying to delete an element with no id", function()
              local values = Faker.fake_entity("api")
              local api = Api(values, dao)

              -- Fail Delete
              local success, err = api:delete()
              assert.falsy(success)
              assert.are.same("Cannot delete an entire collection", err.message)
            end)

          end)
          
        end)
      end
    end)
  end)
end)
