local utils = require "apenode.tools.utils"
local configuration = require "spec.unit.daos.cassandra.configuration"
local Plugin = require "apenode.models.plugin"

local configuration, dao_factory = utils.load_configuration_and_dao(configuration)

describe("BaseDao", function()
  --[[
  setup(function()
    dao_factory:seed(true)
  end)

  teardown(function()
    dao_factory:drop()
  end)
  --]]
  describe("do something", function()


    local res, err = Plugin.find_one({name="cazzo", api_id="a3b2123b-f2ea-4f69-cf4d-887094191eca"}, dao_factory)
    print(err)

    --it("should do something", function()
      --Account({}, dao_factory):save()
      --print(inspect(Account.find_one({id = "de72210d-abd6-42c3-c217-2479e7812661"}, dao_factory)))
      --local res, err = Account.find({created_at=1420681471000}, 10, 10, dao_factory)
      --local res, err = dao_factory.accounts:update({provider_id = "hello22222"}, {provider_id = "hello"})
      --print(inspect(res))
      --print(inspect(err))
    --end)
  end)

end)
