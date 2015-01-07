local configuration = require "spec.unit.daos.cassandra.dao_configuration"
local CassandraFactory = require "apenode.dao.cassandra"
local Account = require "apenode.models.account"

local dao_factory = CassandraFactory(configuration)

describe("BaseDao", function()

  setup(function()
    --  dao_factory:populate(true)
  end)

  --[[
  teardown(function()
    dao_factory:drop()
  end)
  --]]

end)
