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

return AbstractBaseDAO
