local utils = require "apenode.tools.utils"
local dao_configuration = require "spec.database.dao_configuration"

local SQLiteFactory = require "apenode.dao.sqlite.factory"
local dao_factory = SQLiteFactory(dao_configuration.sqlite)

describe("Metrics SQLite DAO", function()

  setup(function()
    dao_factory:prepare()
    dao_factory:seed()
  end)

  teardown(function()
    dao_factory:drop()
    dao_factory:close()
  end)

  describe("#insert_or_update()", function()

    it("should throw an error as it is not supported", function()
      assert.has_error(function() dao_factory.metrics:insert_or_update() end)
    end)

  end)

  describe("#increment_metric()", function()

    it("should create the metric if not already existing", function()
      local inserted, err = dao_factory.metrics:increment(1, 1, nil, "new_metric_1", 123, "second")
      assert.falsy(err)
      assert.truthy(inserted)
      assert.truthy(inserted.value)
    end)

    it("should start the value to 1 and have a step of 1 by default", function()
      local inserted, err = dao_factory.metrics:increment(1, 1, nil, "new_metric_2", 123, "second")
      assert.falsy(err)
      assert.are.same(1, inserted.value)
    end)

    it("should increment the metric by 1 if metric exists and no step is given", function()
      local inserted, err = dao_factory.metrics:increment(1, 1, nil, "new_metric_1", 123, "second")
      assert.falsy(err)
      assert.truthy(inserted)
      assert.are.same(2, inserted.value)
    end)

    it("should increment the metric by step if metric exits and step is given", function()
      local inserted, err = dao_factory.metrics:increment(1, 1, nil, "new_metric_1", 123, "second", 4)
      assert.falsy(err)
      assert.truthy(inserted)
      assert.are.same(6, inserted.value)
    end)

    it("should increment the metric and retrieve it", function()
      local inserted, err = dao_factory.metrics:increment(1, 1, nil, "new_metric_3", 123, "second", 1)
      assert.falsy(err)
      assert.truthy(inserted)
      assert.are.same(1, inserted.value)

      local result, err = dao_factory.metrics:find_one {
        api_id = 1,
        application_id = 1,
        name = "new_metric_3",
        timestamp = 123,
        period = "second"
      }

      assert.falsy(err)
      assert.are.same(1, result.value)
    end)

    it("should increment the metric on IP address and retrieve it", function()
      local inserted, err = dao_factory.metrics:increment(1, nil, "127.0.0.1", "new_metric_4", 123, "second", 1)
      assert.falsy(err)
      assert.truthy(inserted)
      assert.are.same(1, inserted.value)

      local result, err = dao_factory.metrics:find_one {
        api_id = 1,
        origin_ip = "127.0.0.1",
        name = "new_metric_4",
        timestamp = 123,
        period = "second"
      }

      assert.falsy(err)
      assert.are.same(1, result.value)
    end)

    it("should find one metric when calling :find() with correct arguments", function()
      local results, count, err = dao_factory.metrics:find {
        api_id = 1,
        origin_ip = "127.0.0.1",
        name = "new_metric_4",
        timestamp = 123,
        period = "second"
      }

      assert.falsy(err)
      assert.are.same(1, results[1].value)
    end)

  end)

  describe("#delete()", function()

    it("should delete an existing metric", function()
      local count, err = dao_factory.metrics:delete(1, 1, nil, "new_metric_1", 123, "second")
      assert.falsy(err)
      assert.are.same(1, count)
      local result, err = dao_factory.metrics:find_one {
        api_id = 1,
        application_id = 1,
        name = "new_metric_1",
        timestamp = 123
      }

      assert.falsy(err)
      assert.falsy(result)
    end)

  end)
end)
