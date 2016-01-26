local BaseDAO = require "kong.base.dao"

local PostgresDAO = BaseDAO:extend()

function PostgresDAO:new(...)
  PostgresDAO.super.new(self, ...)
end

function PostgresDAO:insert()

end

function PostgresDAO:update()

end

function PostgresDAO:delete()

end

function PostgresDAO:find()

end

function PostgresDAO:find_by_primary_key()

end

function PostgresDAO:find_by_keys()

end

function PostgresDAO:count_by_keys()

end

function PostgresDAO:drop()

end

return PostgresDAO
