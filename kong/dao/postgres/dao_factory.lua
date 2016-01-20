local AbstractDAOFactory = require "kong.abstract.dao_factory"

local PostgresDAOFactory = AbstractDAOFactory:extend()

-- Shorthand for accessing one of the underlying DAOs
function PostgresDAOFactory:__index(key)
  if key ~= "daos" and self.daos and self.daos[key] then
    return self.daos[key]
  else
    return PostgresDAOFactory[key]
  end
end

function PostgresDAOFactory:new(properties, plugins, events_handler)
  PostgresDAOFactory.super.new(self, "postgres", properties, properties, plugins, events_handler)
end

function PostgresDAOFactory:execute_queries()

end

return PostgresDAOFactory
