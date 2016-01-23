local Object = require "classic"
local utils = require "kong.tools.utils"

local AbstractBaseDAO = Object:extend()

function AbstractBaseDAO:new(table, schema, session_options, events_handler)
  self.table = table
  self.schema = schema
  self.session_options = session_options
  self.events_handler = events_handler
end

function AbstractBaseDAO:get_session_options()
  return utils.shallow_copy(self.session_options)
end

function AbstractBaseDAO:execute()
  error("execute() is abstract and must be implemented in a subclass", 2)
end

function AbstractBaseDAO:insert()

end

function AbstractBaseDAO:update()

end

function AbstractBaseDAO:find_by_primary_key()

end

function AbstractBaseDAO:find_by_keys()

end

function AbstractBaseDAO:count_by_keys()

end

function AbstractBaseDAO:find()

end

function AbstractBaseDAO:delete()

end

function AbstractBaseDAO:drop()

end

return AbstractBaseDAO
