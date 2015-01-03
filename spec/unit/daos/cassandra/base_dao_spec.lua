local configuration = require "spec.unit.daos.cassandra.dao_configuration"
local CassandraFactory = require "apenode.dao.cassandra"
local Account = require "apenode.models.account"

local inspect = require "inspect"

local dao_factory = CassandraFactory(configuration)
local daos = {
  api = dao_factory.apis,
  account = dao_factory.accounts,
  application = dao_factory.applications
}

describe("BaseDao", function()

  setup(function()
    local results, count = dao_factory.accounts:find({provider_id = "scemo"})
    print(inspect(results))
    print(count)
  --  dao_factory:populate(true)
  end)

  --[[
  teardown(function()
   dao_factory:drop()
  end)
  --]]

end)
