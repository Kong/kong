local configuration = require "spec.unit.daos.cassandra.dao_configuration"
local CassandraFactory = require "apenode.dao.cassandra"

local dao_factory = CassandraFactory(configuration)
local daos = {
  api = dao_factory.apis,
  account = dao_factory.accounts,
  application = dao_factory.applications
}

describe("BaseDao", function()
  --[[
  setup(function()
   dao_factory:populate(true)
  end)

  teardown(function()
   dao_factory:drop()
  end)
  --]]

end)
