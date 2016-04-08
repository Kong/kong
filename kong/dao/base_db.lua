local Object = require "classic"
local utils = require "kong.tools.utils"

local BaseDB = Object:extend()

function BaseDB:new(db_type, conn_opts)
  self.options = conn_opts
  self.db_type = db_type
end

function BaseDB:init()
  -- to be implemented in child
  -- called by init_by_worker for DB specific initialization
end

function BaseDB:_get_conn_options()
  return utils.shallow_copy(self.options)
end

function BaseDB:query(query)
  -- to be implemented in child
end

function BaseDB:insert(model)
  -- to be implemented in child
end

function BaseDB:find()
  -- to be implemented in child
end

function BaseDB:find_all()
  -- to be implemented in child
end

function BaseDB:count()
  -- to be implemented in child
end

function BaseDB:update()
  -- to be implemented in child
end

function BaseDB:delete()
  -- to be implemented in child
end

return BaseDB
