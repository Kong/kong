local configuration = require "spec.unit.daos.sqlite.dao_configuration"
local SQLiteFactory = require "apenode.dao.sqlite"

local dao_factory = SQLiteFactory(configuration)

describe("DetailedDaos", function()

  setup(function()
    dao_factory:populate(true)
  end)

  teardown(function()
    dao_factory:drop()
    dao_factory:close()
  end)

  describe("MetricsDao", function()

    describe("#insert_or_update()", function()
      it("should throw an error as it is not supported", function()
        assert.has_error(function() dao_factory.metrics:insert_or_update() end)
      end)
    end)

    describe("#increment_metric()", function()
      it("should create the metric if not already existing", function()
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
        local count, err = dao_factory.metrics:delete(1, 1, "new_metric_1", 123)
        assert.falsy(err)
        assert.are.same(1, count)
        local result, err = dao_factory.metrics:find_one(1, 1, "new_metric_1", 123)
        assert.falsy(err)
        assert.falsy(result)
      end)
    end)

  end)

  describe("PluginsDao", function()

    describe("#find()", function()
      it("find plugins with table args", function()
        local result, count, err = dao_factory.plugins:find({
          value = {
            authentication_type = "query",
            authentication_key_names = { "apikey" }
          }
        })
        assert.falsy(err)
        assert.are.equal(996, count)
      end)
      it("find plugins with wrong table args", function()
        local result, count, err = dao_factory.plugins:find({
          value = {
            authentication_type = "query",
            authentication_key_names = { "apikey", "x-api-key2" }
          }
        })
        assert.falsy(err)
        assert.are.equal(0, count)
      end)
      it("find plugins with composite table args", function()
        local result, count, err = dao_factory.plugins:find({
          api_id = 1,
          value = {
            authentication_type = "query",
            authentication_key_names = { "apikey" }
          }
        })
        assert.falsy(err)
        assert.are.equal(1, count)
      end)
      it("find plugins with composite table args in reversed order", function()
        local result, count, err = dao_factory.plugins:find({
          value = {
            authentication_key_names = { "apikey" },
            authentication_type = "query"
          },
          api_id = 1
        })
        assert.falsy(err)
        assert.are.equal(1, count)
      end)
      it("find plugins with composite table args in reversed order should return zero", function()
        local result, count, err = dao_factory.plugins:find({
          value = {
            authentication_key_names = { "apikey" },
            authentication_type = "query"
          },
          api_id = 2
        })
        assert.falsy(err)
        assert.are.equal(0, count)
      end)
    end)

  end)

end)
