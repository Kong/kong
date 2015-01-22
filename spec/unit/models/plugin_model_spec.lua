local utils = require "apenode.tools.utils"
local Plugin = require "apenode.models.plugin"
local configuration = require "spec.unit.daos.sqlite.configuration"

local configuration, dao_factory = utils.load_configuration_and_dao(configuration)

describe("Metric Model", function()

  setup(function()
    dao_factory:prepare()
    dao_factory:seed()
  end)

  teardown(function()
    dao_factory:drop()
    dao_factory:close()
  end)

  describe("#init()", function()
    it("should find the plugin", function()
      local res, err = Plugin.find_one({
        api_id = 6,
        application_id = 3,
        name = "ratelimiting"
      }, dao_factory)

      assert.falsy(err)
      assert.truthy(res)
      assert.are.same({ api_id = 6,
                        application_id = 3,
                        id = 7,
                        name = "ratelimiting",
                        value = {
                          limit = 4,
                          period = "minute"
                        }
                      }, res._t)
    end)
  end)

end)
