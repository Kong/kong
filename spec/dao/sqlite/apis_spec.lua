local inspect = require "inspect"
local dao = require "apenode.dao.sqlite"
local apisdao = dao.apis

describe("SQLite APIsDao #dao", function()

  setup(function()
    dao.populate()
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

      it("should return an error if", function()

      end)

    end)

    describe("#get_by_id()", function()

      it("should get an API by id", function()
        local result = apisdao:get_by_id(4)
        assert.truthy(result)
        assert.are.equal(4, result.id)
      end)

      it("should return nil if API does not exist", function()
        local result = apisdao:get_by_id(999)
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

      it("should save an API", function()
        local result, err = apisdao:save({
          name = "new api",
          public_dns = "httpbin.com",
          target_url = "http://httpbin.org",
          authentication_type = "query"
        })

        assert.falsy(err)
        assert.truthy(result)
      end)

      it("should return an error if failed", function()
        local result, err = apisdao:save({
          name = "new api"
        })

        assert.truthy(err)
        assert.falsy(result)
      end)

    end)

    describe("#update()", function()

      it("should update an API", function()
        local result, err = apisdao:update({
          id = 1,
          name = "hello"
        })

        assert.falsy(err)
        assert.truthy(result)

        result, err = apisdao:get_by_id(1)
        assert.are.same("hello", result.name)
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
