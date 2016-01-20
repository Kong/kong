local AbstractBaseDAO = require "kong.abstract.base_dao"

local PostgresBaseDAO = AbstractBaseDAO:extend()

function PostgresBaseDAO:new(...)
  PostgresBaseDAO.super.new(self, ...)
end

function PostgresBaseDAO:insert()

end

function PostgresBaseDAO:update()

end

function PostgresBaseDAO:delete()

end

-- A page matching WHERE
function PostgresBaseDAO:find()

end

-- A single row
function PostgresBaseDAO:find_by_primary_key()

end

-- A page matching WHERE, for Postgres, same as :find()
function PostgresBaseDAO:find_by_keys()

end

function PostgresBaseDAO:count_by_keys()

end

function PostgresBaseDAO:drop()

end

return PostgresBaseDAO
