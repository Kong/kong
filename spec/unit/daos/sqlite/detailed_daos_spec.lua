local configuration = require "spec.unit.daos.sqlite.dao_configuration"
local SQLiteFactory = require "apenode.dao.sqlite"

local dao_factory = SQLiteFactory(configuration)

describe("DetailedDaos", function()

  setup(function()
    dao_factory:populate(true)
  end)

  teardown(function()
    dao_factory:drop()
  end)

  describe("APIsDao", function()
--[[
    describe("authentication_key_names serialization", function()
      describe("#save()", function()
        it("should serialize the authentication_key_names property", function()
          local api_to_save = dao_factory.fake_entity("api")
          local saved_api = dao_factory.apis:save(api_to_save)
          assert.truthy(saved_api.authentication_key_names)
          assert.are.same("table", type(saved_api.authentication_key_names))
          assert.are.same({ "X-Mashape-Key", "X-Apenode-Key" }, saved_api.authentication_key_names)
        end)
        it("should be an empty table with an empty authentication_key_names value", function()
          local api_to_save = dao_factory.fake_entity("api")
          api_to_save.authentication_key_names = nil
          local saved_api = dao_factory.apis:save(api_to_save)
          assert.truthy(saved_api.authentication_key_names)
          assert.are.same("table", type(saved_api.authentication_key_names))
          assert.are.same({}, saved_api.authentication_key_names)
        end)
      end)
    end)
--]]
  end)

  describe("MetricsDao", function()

    describe("#insert_or_update()", function()
      it("should throw an error as it is not implemented", function()
        assert.has_error(function() dao_factory.metrics:insert_or_update() end)
      end)

    end)
--[[
    describe("#increment_metric()", function()
      it("should create the metric of not already existing", function()
        local inserted, err = dao_factory.metrics:increment_metric(1, 1, "new_metric_1", 123)
        assert.falsy(err)
        assert.truthy(inserted)
        assert.truthy(inserted.value)
      end)
      it("should start the value to 1 and have a step of 1 by default", function()
        local inserted, err = dao_factory.metrics:increment_metric(1, 1, "new_metric_2", 123)
        assert.falsy(err)
        assert.are.same(1, inserted.value)
      end)
      it("should increment the metric by 1 if metric exists and no step is given", function()
        local inserted, err = dao_factory.metrics:increment_metric(1, 1, "new_metric_1", 123)
        assert.falsy(err)
        assert.truthy(inserted)
        assert.are.same(2, inserted.value)
      end)
      it("should increment the metric by step if metric exits and step is given", function()
        local inserted, err = dao_factory.metrics:increment_metric(1, 1, "new_metric_1", 123, 4)
        assert.falsy(err)
        assert.truthy(inserted)
        assert.are.same(6, inserted.value)
      end)
    end)

    describe("#delete()", function()
      it("should delete an existing metric", function()
        local success, err = dao_factory.metrics:delete(1, 1, "new_metric_1", 123)
        assert.falsy(err)
        local result, err = dao_factory.metrics:retrieve_metric(1, 1, "new_metric_1", 123)
        assert.falsy(err)
        assert.falsy(result)
      end)
    end)
]]
  end)

end)
