local configuration = require "spec.unit.daos.cassandra.dao_configuration"
local CassandraFactory = require "apenode.dao.cassandra"
local Account = require "apenode.models.account"

local inspect = require "inspect"

local dao_factory = CassandraFactory(configuration)

describe("BaseDao", function()

  setup(function()

   --local res, err = Account({}, dao_factory):save()

   local res, err = Account.find({id = "f2376522-f5d0-4400-c4d9-2b249c2fc613"}, 1, 1, dao_factory)

   for k,v in pairs(res) do
      print(v.crea)
    end


   --print(inspect(err))

   -- local results, err = dao_factory.accounts:insert("63ac8669-adb4-4969-c9f8-fc5ca9fdbda9")
   --print(inspect(results))
   -- print(err)
  --  dao_factory:populate(true)
  end)

  --[[
  teardown(function()
   dao_factory:drop()
  end)
  --]]

end)
