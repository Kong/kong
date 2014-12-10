local inspect = require "inspect"
local dao = require "apenode.dao.sqlite"
local apisdao = dao.apis
local accountsdao = dao.accounts

describe("SQLite DAO #dao", function()

  setup(function()
    dao.populate()
  end)

  describe("AccountsDao", function()

    describe("#get_all()", function()

      it("should return the 1st page of 30 entities by default", function()
        local result = accountsdao:get_all()
        assert.are.equal(30, table.getn(result))
        assert.are.equal(1, result[1].id)
      end)

      it("should be able to specify a page size", function()
        local result = accountsdao:get_all(1, 5)
        assert.are.equal(5, table.getn(result))
        assert.are.equal(1, result[1].id)
        assert.are.equal(4, result[4].id)
      end)

      it("should limit the page size to 100", function()
        local result = accountsdao:get_all(8, 1000)
        assert.are.equal(100, table.getn(result))
      end)

      it("should be able to query any page from a paginated entity", function()
        local result = accountsdao:get_all(3, 6)
        assert.are.equal(6, table.getn(result))
        assert.are.equal(13, result[1].id)
        assert.are.equal(16, result[4].id)
      end)

      it("should be able to query the last page from a paginated entity", function()
        local result = accountsdao:get_all(8, 5)
        assert.are.equal(5, table.getn(result))
        assert.are.equal(36, result[1].id)
        assert.are.equal(40, result[5].id)
      end)

      it("should return the total number of accounts too", function()
        local result, count = accountsdao:get_all()
        assert.are.equal(1000, count)
      end)

    end)

    describe("#get_by_id()", function()

      it("should get an account by id", function()
        local result = accountsdao:get_by_id(4)
        assert.truthy(result)
        assert.are.equal(4, result.id)
      end)

      it("should return nil if API does not exist", function()
        local result = accountsdao:get_by_id(9999)
        assert.falsy(result)
        assert.are.equal(nil, result)
      end)

    end)

    describe("#get_by_provider_id()", function()

      it("should get an account by provider_id", function()
        local result, err = accountsdao:get_by_provider_id("provider3")
        assert.truthy(result)
        assert.are.equal("provider3", result.provider_id)
      end)

      it("should return nil if account does not exist", function()
        local result = accountsdao:get_by_provider_id("nothing")
        assert.falsy(result)
        assert.are.equal(nil, result)
      end)

    end)

    describe("#save()", function()

      it("should save an account and return the id", function()
        local saved_id, err = accountsdao:save {
          provider_id = "new id"
        }

        assert.falsy(err)
        assert.truthy(saved_id)

        local result = accountsdao:get_by_id(saved_id)
        assert.truthy(result)
        assert.are.same(saved_id, result.id)
      end)

      it("should return an error if failed", function()
        local saved_id, err = accountsdao:save {
          provider_id = "provider1"
        }

        assert.truthy(err)
        assert.falsy(saved_id)
      end)

      it("should default the created_at timestamp", function()
        local saved_id = accountsdao:save {
          provider_id = "another new id"
        }

        local result = accountsdao:get_by_id(saved_id)
        assert.truthy(result.created_at)
      end)

    end)

    describe("#update()", function()

      it("should update an account", function()
        local result, err = accountsdao:update {
          id = 1,
          provider_id = "updated_id"
        }

        assert.falsy(err)
        assert.truthy(result)

        result, err = accountsdao:get_by_id(1)
        assert.falsy(err)
        assert.is_true(result.provider_id == "updated_id")
        -- This does not work. wtf?
        --assert.are.equal("udpated_id", result.provider_id)
      end)

    end)

    describe("#delete()", function()

      it("should delete an account", function()
        local result, err = accountsdao:delete(1)
        assert.falsy(err)
        assert.truthy(result)

        result, err = accountsdao:get_by_id(1)
        assert.falsy(err)
        assert.falsy(result)
      end)

    end)

  end)

  describe("APIsDao", function()

    describe("#get_all()", function()

      it("should return the 1st page of 30 entities by default", function()
        local result = apisdao:get_all()
        assert.are.equal(30, table.getn(result))
        assert.are.equal(1, result[1].id)
      end)

      it("should be able to specify a page size", function()
        local result = apisdao:get_all(1, 5)
        assert.are.equal(5, table.getn(result))
        assert.are.equal(1, result[1].id)
        assert.are.equal(4, result[4].id)
      end)

      it("should limit the page size to 100", function()
        local result = apisdao:get_all(8, 1000)
        assert.are.equal(100, table.getn(result))
      end)

      it("should be able to query any page from a paginated entity", function()
        local result = apisdao:get_all(3, 6)
        assert.are.equal(6, table.getn(result))
        assert.are.equal(13, result[1].id)
        assert.are.equal(16, result[4].id)
      end)

      it("should be able to query the last page from a paginated entity", function()
        local result = apisdao:get_all(8, 5)
        assert.are.equal(5, table.getn(result))
        assert.are.equal(36, result[1].id)
        assert.are.equal(40, result[5].id)
      end)

      it("should return the total number of APIs too", function()
        local result, count = apisdao:get_all()
        assert.are.equal(1000, count)
      end)

    end)

    describe("#get_by_id()", function()

      it("should get an API by id", function()
        local result = apisdao:get_by_id(4)
        assert.truthy(result)
        assert.are.equal(4, result.id)
      end)

      it("should return nil if API does not exist", function()
        local result = apisdao:get_by_id(9999)
        assert.falsy(result)
        assert.are.equal(nil, result)
      end)

    end)

    describe("#get_by_host()", function()

      it("should get an API by host", function()
        local result, err = apisdao:get_by_host("apebin1.com")
        assert.truthy(result)
        assert.are.equal("apebin1.com", result.public_dns)
      end)

      it("should return nil if API does not exist", function()
        local result = apisdao:get_by_host("nothing")
        assert.falsy(result)
        assert.are.equal(nil, result)
      end)

    end)

    describe("#save()", function()

      it("should save an API and return the id", function()
        local saved_id, err = apisdao:save {
          name = "new api"
        }

        assert.falsy(err)
        assert.truthy(saved_id)

        local result = apisdao:get_by_id(saved_id)
        assert.truthy(result)
        assert.are.same(saved_id, result.id)
      end)

      it("should return an error if failed", function()
        local saved_id, err = apisdao:save {
          name = "new api"
        }

        assert.truthy(err)
        assert.falsy(saved_id)
      end)

      it("should default the created_at timestamp", function()
        local saved_id = apisdao:save {
          name = "my api"
        }

        local result = apisdao:get_by_id(saved_id)
        assert.truthy(result.created_at)
      end)

    end)

    describe("#update()", function()

      it("should update an API", function()
        local result, err = apisdao:update {
          id = 1,
          name = "hello"
        }

        assert.falsy(err)
        assert.truthy(result)

        result, err = apisdao:get_by_id(1)
        assert.falsy(err)
        assert.are.equal("hello", result.name)
      end)

    end)

    describe("#delete()", function()

      it("should delete an API", function()
        local result, err = apisdao:delete(1)
        assert.falsy(err)
        assert.truthy(result)

        result, err = apisdao:get_by_id(1)
        assert.falsy(err)
        assert.falsy(result)
      end)

    end)

  end)

end)
