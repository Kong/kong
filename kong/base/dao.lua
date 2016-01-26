local Object = require "classic"
local utils = require "kong.tools.utils"

local BaseDAO = Object:extend()

function BaseDAO:new(schema, session_options, events_handler)
  self.schema = schema
  self.session_options = session_options
  self.events_handler = events_handler
end

function BaseDAO:get_session_options()
  return utils.shallow_copy(self.session_options)
end

function BaseDAO:execute()
  error("execute() is abstract and must be implemented in a subclass", 2)
end

function BaseDAO:insert()

end

function BaseDAO:update()

end

function BaseDAO:find_by_primary_key()

end

function BaseDAO:find_by_keys()

end

function BaseDAO:count_by_keys()

end

function BaseDAO:find()

end

function BaseDAO:delete()

end

function BaseDAO:drop()

end

return BaseDAO
