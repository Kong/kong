-- Inserted variables
local Object = require "classic"
local dao_factory = require "apenode.dao.cassandra"


-- Migration interface
local Migration = Object:extend()

function Migration:new(dao_configuration)
  self.dao = dao_factory(dao_configuration.properties, true)
end

function Migration:up()
  self.dao:execute [[

  ]]

  self.dao:close()
end

function Migration:down()
  self.dao.execute [[

  ]]

  self.dao:close()
end

return Migration
    