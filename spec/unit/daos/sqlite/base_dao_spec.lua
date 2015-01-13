local utils = require "apenode.utils"
local configuration = require "spec.unit.daos.sqlite.configuration"
local SQLiteFactory = require "apenode.dao.sqlite"

local configuration, dao_properties = utils.parse_configuration(configuration)
local dao_factory = SQLiteFactory(dao_properties)
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
    dao_factory:close()
  end)

  describe("#find_one()", function()
    it("should return an entity given the id field", function()
      local entity, err = dao_factory.apis:find_one { id = 1 }
      assert.falsy(err)
      assert.truthy(entity)
      assert.truthy(entity.public_dns)
      end)
    it("should find an entity given any field", function()
      local entity, err = dao_factory.apis:find_one { public_dns = "test.com" }
      assert.falsy(err)
      assert.truthy(entity)
      assert.are.same("test.com", entity.public_dns)
    end)
    it("should return nil if entity does not exist", function()
      local entity, err = dao_factory.apis:find_one { public_dns = "mashape.com" }
      assert.falsy(err)
      assert.falsy(entity)
    end)
    it("shoud throw an error if the satement is invalid", function()
      assert.has_error(function()
        local entity, err = dao_factory.apis:find_one { foo = "bar" }
      end)
    end)
  end)

  describe("#find()", function()
    it("should return the 1st page of 30 entities by default", function()
      local result, count, err = dao_factory.apis:find()
      assert.falsy(err)
      assert.are.equal(30, #result)
      assert.are.equal(1, result[1].id)
    end)
    it("should be able to specify a page size", function()
      local result, count, err = dao_factory.apis:find(1, 5)
      assert.falsy(err)
      assert.are.equal(5, #result)
      assert.are.equal(1, result[1].id)
      assert.are.equal(4, result[4].id)
    end)
    it("should limit the page size to 100", function()
      local result, count, err = dao_factory.apis:find(8, 1000)
      assert.falsy(err)
      assert.are.equal(100, #result)
    end)
    it("should be able to query any page from a paginated entity", function()
      local result, count, err = dao_factory.apis:find(3, 6)
      assert.falsy(err)
      assert.are.equal(6, #result)
      assert.are.equal(13, result[1].id)
      assert.are.equal(16, result[4].id)
    end)
    it("should be able to query the last page from a paginated entity", function()
      local result, count, err = dao_factory.apis:find(8, 5)
      assert.falsy(err)
      assert.are.equal(5, #result)
      assert.are.equal(36, result[1].id)
      assert.are.equal(40, result[5].id)
    end)
    it("should return the total number of entity too", function()
      local result, count, err = dao_factory.apis:find()
      assert.falsy(err)
      assert.are.equal(1000, count)
    end)
    it("should return paginated entites with a WHERE statement", function()
      local result, count, err = dao_factory.apis:find({ target_url = "http://httpbin.org" })
      assert.falsy(err)
      assert.are.equal(6, count)
      assert.are.equal("table", type(result))
    end)
     it("should handle empty args", function()
      local result, count, err = dao_factory.apis:find({})
      assert.falsy(err)
      assert.are.equal(1000, count)
      result, count, err = dao_factory.apis:find()
      assert.falsy(err)
      assert.are.equal(1000, count)
    end)
    it("shoud throw an error if the satement is invalid", function()
      assert.has_error(function()
        local entity, err = dao_factory.apis:find { foo = "bar" }
      end)
    end)
  end)

  describe("#update()", function()
    it("should support partial update", function()
      local existing_entity = dao_factory.apis:find_one { id = 1 }
      existing_entity.public_dns = "hello.com"

      local updated_rows, err = dao_factory.apis:update(existing_entity)
      assert.falsy(err)
      assert.are.same(1, updated_rows)
    end)
    it("should return the number of rows affected", function()
      local existing_entity = dao_factory.apis:find_one { id = 1 }
      existing_entity.public_dns = "hello2.com"

      local updated_rows, err = dao_factory.apis:update(nil)
      assert.falsy(err)
      assert.are.same(0, updated_rows)
    end)
  end)

  for dao_name, dao in pairs(daos) do
    describe(dao_name, function()

      describe("#insert()", function()
        it("should insert an entity", function()
          local random_entity = dao_factory.fake_entity(dao_name)
          local saved_entity, err = dao:insert(random_entity)
          assert.falsy(err)
          assert.truthy(saved_entity)

          local result, err = dao:find_one { id = saved_entity.id }
          assert.falsy(err)
          assert.truthy(result)
          random_entity.id = saved_entity.id
          assert.are.same(random_entity, saved_entity)
        end)
        it("should return the created entity", function()
          local random_entity = dao_factory.fake_entity(dao_name)
          local saved_entity = dao:insert(random_entity)
          random_entity.id = saved_entity.id
          random_entity.created_at = saved_entity.created_at
          for k,v in pairs(random_entity) do
            assert.truthy(saved_entity[k])
          end
        end)
        it("should return nil if given nil to insert", function()
          local saved_entity, err = dao:insert(nil)
          assert.falsy(err)
          assert.falsy(saved_entity)
        end)
      end)

      describe("#update()", function()
        it("should update an entity if already existing", function()
          local existing_entity = dao:find_one { id = 1 }
          local random_entity = dao_factory.fake_entity(dao_name)

          -- Replace all fields in the entity
          for k,v in pairs(random_entity) do
            existing_entity[k] = v
          end

          local updated_entity, err = dao:update(existing_entity)
          assert.falsy(err)
          assert.truthy(updated_entity)

          updated_entity = dao:find_one { id = 1 }

          -- Assert all fields have been updated
          for k,v in pairs(random_entity) do
            assert.are.same(random_entity[k], updated_entity[k])
          end
        end)
        it("should return nil if given nil to insert", function()
          local updated_entity, err = dao:update(nil)
          assert.falsy(err)
          assert.are.same(0, updated_entity)
        end)
        it("should throw an error if invalid column is updated", function()
          local existing_entity = dao:find_one { id = 1 }
          existing_entity.foo = "hello.com"

          assert.has_error(function()
            dao:update(existing_entity)
          end)
        end)
      end)

      describe("#insert_or_update()", function()
        it("should save an entity if not present", function()
          local random_entity = dao_factory.fake_entity(dao_name)
          local saved_entity, err = dao:insert_or_update(random_entity)
          assert.falsy(err)
          assert.truthy(saved_entity)

          local result, err = dao:find_one { id = saved_entity.id }
          assert.falsy(err)
          assert.truthy(result)
          random_entity.id = saved_entity.id
          assert.are.same(random_entity, saved_entity)
        end)
        it("should return the created entity", function()
          local random_entity = dao_factory.fake_entity(dao_name)
          local saved_entity = dao:insert_or_update(random_entity)
          random_entity.id = saved_entity.id
          random_entity.created_at = saved_entity.created_at
          for k,v in pairs(random_entity) do
            assert.truthy(saved_entity[k])
          end
        end)
        it("should update an entity if already existing", function()
          local existing_entity = dao:find_one { id = 1 }
          local random_entity = dao_factory.fake_entity(dao_name)

          -- Replace all fields in the entity
          for k,v in pairs(random_entity) do
            existing_entity[k] = v
          end

          local updated_entity, err = dao:insert_or_update(existing_entity)
          assert.falsy(err)
          assert.truthy(updated_entity)

          updated_entity = dao:find_one { id = 1 }

          -- Assert all fields have been updated
          for k,v in pairs(random_entity) do
            assert.are.same(random_entity[k], updated_entity[k])
          end
        end)
        it("should return nil if given nil to insert", function()
          local saved_entity, err = dao:insert_or_update(nil)
          assert.falsy(err)
          assert.falsy(saved_entity)
        end)
      end)

      describe("#delete_by_id()", function()
        it("should delete an entity by key", function()
          local result, err = dao:delete_by_id(1)
          assert.falsy(err)
          assert.truthy(result)
          result, err = dao:find_one { id = 1 }
          assert.falsy(err)
          assert.falsy(result)
        end)
        it("should delete an object by composite key", function()
          local random_entity = dao_factory.fake_entity(dao_name)
          -- Save entity
          local saved_entity, err = dao:insert(random_entity)
          assert.falsy(err)
          assert.truthy(saved_entity)
          -- Check if saved
          local result, err = dao:find_one { id = saved_entity.id }
          assert.falsy(err)
          assert.truthy(result)
          -- Delete entity
          local result, err = dao:delete_by_id(saved_entity.id)
          assert.falsy(err)
          assert.truthy(result)
          -- Check if deleted
          local result, err = dao:find_one { id = saved_entity.id }
          assert.falsy(err)
          assert.falsy(result)
        end)
        it("should return the number of deleted rows", function()
          local result, err = dao:delete_by_id(2)
          assert.falsy(err)
          assert.are.same(1, result)
        end)
        it("should prevent the execution if passed key is about to delete the entire collection", function()
          local result, err = dao:delete_by_id()
          assert.truthy(err)
          assert.falsy(result)
          local result, err = dao:delete_by_id()
          assert.truthy(err)
          assert.falsy(result)
          assert.are.same("Cannot delete an entire collection", err.message)
        end)
      end)

    end)
  end

end)
