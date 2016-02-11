local inspect = require "inspect"

local Object = require "classic"
local utils = require "kong.tools.utils"

local function debug_log(self, ...)
  local prefix = "[DB:"..self.db_type.."]"
  if ngx ~= nil then
    --ngx.log(ngx.DEBUG, prefix, inspect(...))
    --print(prefix, inspect(...))
  else
    print(prefix, inspect(...))
  end
end

local BaseDB = Object:extend()

function BaseDB:new(db_type, conn_opts)
  self.options = conn_opts
  self.db_type = db_type
end

function BaseDB:_get_conn_options()
  return utils.shallow_copy(self.options)
end

function BaseDB:init_db()

end

function BaseDB:query(query)
  --debug_log(self, query)
  -- to be implemented in child
end

function BaseDB:insert(model)
  -- to be implemented in child
end

function BaseDB:select()
  -- to be implemented in child
end

return BaseDB
