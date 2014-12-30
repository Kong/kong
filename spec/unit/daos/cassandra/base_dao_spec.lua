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
    local entity = dao_factory.accounts:insert({provider_id = "scemo", created_at = os.time()})
    print(inspect(entity))
  --  dao_factory:populate(true)
  end)

  --[[
  teardown(function()
   dao_factory:drop()
  end)
  --]]

end)
