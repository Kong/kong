local dao = require("apenode.dao.sqlite")
local apisdao = dao.apis

describe("SQLite APIsDao #dao", function()

  setup(function()
    dao.populate()
  end)

  describe("APIsDao", function()

    describe("#get_all()", function()

      it("should", function()
        local retrievedApis = apisdao:get_all()
        assert.are.equal(1, table.getn(retrievedApis))
      end)

    end)

  end)

end)
