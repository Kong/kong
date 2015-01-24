local utils = require "apenode.tools.utils"
local dao_configuration = require "spec.database.dao_configuration"

local SQLiteFactory = require "apenode.dao.sqlite.factory"
local dao_factory = SQLiteFactory(dao_configuration.sqlite)

describe("BaseDao", function()

  setup(function()
    dao_factory:prepare()
    dao_factory:seed(true)
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

    it("shoud throw an error if the statement is invalid", function()
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
end)
