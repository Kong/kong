local configuration = require "spec.dao.sqlite.dao_configuration"
local SQLiteFactory = require "apenode.dao.sqlite"

local dao_factory = SQLiteFactory(configuration)
local daos = {
  api = dao_factory.apis,
  account = dao_factory.accounts,
  application = dao_factory.applications
}

describe("BaseDao", function()

  setup(function()
    dao_factory:populate(true)
  end)

  teardown(function()
    dao_factory:drop()
  end)

  for dao_name, dao in pairs(daos) do
    describe(dao_name, function()

      describe("#get_all()", function()
        it("should return the 1st page of 30 entities by default", function()
          local result = dao:get_all()
          assert.are.equal(30, table.getn(result))
          assert.are.equal(1, result[1].id)
        end)
        it("should be able to specify a page size", function()
          local result = dao:get_all(1, 5)
          assert.are.equal(5, table.getn(result))
          assert.are.equal(1, result[1].id)
          assert.are.equal(4, result[4].id)
        end)
        it("should limit the page size to 100", function()
          local result = dao:get_all(8, 1000)
          assert.are.equal(100, table.getn(result))
        end)
        it("should be able to query any page from a paginated entity", function()
          local result = dao:get_all(3, 6)
          assert.are.equal(6, table.getn(result))
          assert.are.equal(13, result[1].id)
          assert.are.equal(16, result[4].id)
        end)
        it("should be able to query the last page from a paginated entity", function()
          local result = dao:get_all(8, 5)
          assert.are.equal(5, table.getn(result))
          assert.are.equal(36, result[1].id)
          assert.are.equal(40, result[5].id)
        end)
        it("should return the total number of entity too", function()
          local result, count = dao:get_all()
          assert.are.equal(1000, count)
        end)
      end)

      describe("#get_by_id()", function()
        it("should get an entity by id", function()
          local result = dao:get_by_id(4)
          assert.truthy(result)
          assert.are.equal(4, result.id)
        end)
        it("should return nil if entity does not exist", function()
          local result = dao:get_by_id(9999)
          assert.falsy(result)
          assert.are.equal(nil, result)
        end)
      end)

      describe("#save()", function()
        it("should save an entity", function()
          local random_entity = dao_factory.fake_entity(dao_name)
          local saved_entity, err = dao:save(random_entity)
          assert.falsy(err)
          assert.truthy(saved_entity)
        end)
        if dao_name ~= "application" then
          it("should return an error if failed", function()
            local random_entity = dao_factory.fake_entity(dao_name, true)
            local inspect = require "inspect"
            local saved_entity, err = dao:save(random_entity)
            assert.truthy(err)
            assert.falsy(saved_entity)
          end)
        end
        it("should return the created entity", function()
          local random_entity = dao_factory.fake_entity(dao_name)
          local saved_entity, err = dao:save(random_entity)
          random_entity.id = saved_entity.id
          random_entity.created_at = saved_entity.created_at
          for k,v in pairs(random_entity) do
            assert.truthy(saved_entity[k])
          end
        end)
        it("should default the created_at timestamp", function()
          local random_entity = dao_factory.fake_entity(dao_name)
          local saved_entity = dao:save(random_entity)
          assert.truthy(saved_entity.created_at)
        end)
      end)

      describe("#update()", function()
        it("should update an entity", function()
          local random_entity = dao_factory.fake_entity(dao_name)
          random_entity.id = 1
          local result, err = dao:update(random_entity)
          assert.falsy(err)
          assert.truthy(result)
          result, err = dao:get_by_id(1)
          assert.falsy(err)

          if dao_name == "api" then
            assert.are.equal(random_entity.name, result.name)
          elseif dao_name == "account" then
            assert.are.equal(random_entity.provider_id, result.provider_id)
          elseif dao_name == "application" then
            assert.are.equal(random_entity.public_key, result.public_key)
            assert.are.equal(random_entity.secret_key, result.secret_key)
          end
        end)
        it("should return the updated entity", function()
          local random_entity = dao_factory.fake_entity(dao_name)
          random_entity.id = 1
          local result, err = dao:update(random_entity)
          assert.falsy(err)
          assert.is_true(type(result) == "table")
        end)
      end)

      describe("#delete()", function()
        it("should delete an entity", function()
          local result, err = dao:delete(1)
          assert.falsy(err)
          assert.truthy(result)
          result, err = dao:get_by_id(1)
          assert.falsy(err)
          assert.falsy(result)
        end)
      end)

    end)
  end

end)
