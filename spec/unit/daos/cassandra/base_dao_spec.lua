local utils = require "apenode.tools.utils"
local configuration = require "spec.unit.daos.cassandra.configuration"

--local configuration, dao_factory = utils.load_configuration_and_dao(configuration)

describe("BaseDao", function()

  setup(function()
    --dao_factory:seed(true)
  end)

  teardown(function()
    --dao_factory:drop()
    --dao_factory:close()
  end)

  describe("", function()

  end)

end)
