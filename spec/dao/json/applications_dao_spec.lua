require "spec.dao.json.configuration"

describe("JSON ApplicationsDao #dao", function()

  setup(function()
    _G.applicationsdao = require("apenode.dao.json.applications")()
  end)

  teardown(function()
    os.remove(configuration.dao.properties.file_path)
  end)

  describe("ApplicationsDao", function()

    it("should implement BaseDao", function()
      assert.truthy(applicationsdao.save)
      assert.truthy(applicationsdao.get_all)
      assert.truthy(applicationsdao.get_by_id)
      assert.truthy(applicationsdao.delete)
      assert.truthy(applicationsdao.update)
    end)

    describe("#get_by_key()", function()

      it("should return nil if host argument is nil", function()
        local retrievedApp = applicationsdao:get_by_key(nil)
        assert.falsy(retrievedApp)
      end)

      it("should retrieve an Application entity by it's secret_key value", function()
        local app = { secret_key = "abcd" }
        local savedApp = applicationsdao:save(app)

        local retrievedApp = applicationsdao:get_by_key(app.secret_key)
        assert.are.same(savedApp, retrievedApp)
      end)

    end)

  end)

end)
