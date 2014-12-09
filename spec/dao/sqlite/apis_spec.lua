local dao = require("apenode.dao.sqlite")
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

  end)

end)
