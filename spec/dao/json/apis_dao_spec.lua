require "spec.dao.json.configuration"

describe("JSON APIsDao #dao", function()

  setup(function()
    _G.apisdao = require("apenode.dao.json.apis")()
  end)

  teardown(function()
    os.remove(configuration.dao.properties.file_path)
  end)

  describe("APIsDao", function()

    it("should implement BaseDao", function()
      assert.truthy(apisdao.save)
      assert.truthy(apisdao.get_all)
      assert.truthy(apisdao.get_by_id)
      assert.truthy(apisdao.delete)
      assert.truthy(apisdao.update)
    end)

    describe("#get_by_host()", function()

      it("should return nil if host argument is nil", function()
        local retrievedApi = apisdao:get_by_host(nil)
        assert.falsy(retrievedApi)
      end)

      it("should retrieve an API entity by it's public_dns value", function()
        local api = { public_dns = "http://httpbin.org" }
        local savedApi = apisdao:save(api)

        local retrievedApi = apisdao:get_by_host(api.public_dns)
        assert.are.same(savedApi, retrievedApi)
      end)

    end)

  end)

end)
