local utils = require "kong.tools.utils"
local Errors = require "kong.db.errors"

local Fake = {}

local function pk_to_s(schema, pk)
  local buffer = {}
  for i, key in ipairs(schema.primary_key) do
    buffer[i] = pk[key]
  end
  return table.concat(buffer, '-')
end


Fake.CUSTOM_STRATEGIES = {
  routes = require("kong.db.strategies.fake.routes"),
}

function Fake.new(connector, schema)

  return {
    entities = {},

    schema = schema,

    name = schema.name,

    select = function(self, pk, options)
      local found = self.entities[pk_to_s(self.schema, pk)]
      if found then
        return found
      end
      return nil, "Not found", Errors.NOT_FOUND
    end,

    insert = function(self, attributes, options)
      local copy = utils.deep_copy(attributes)
      self.entities[pk_to_s(self.schema, attributes)] = copy
      return copy
    end,

    update = function(self, pk, attributes, options)
      local current = self.entities[pk_to_s(self.schema, pk)]
      local merge   = utils.table_merge(current, attributes)
      self.entities[pk_to_s(self.schema, pk)] = merge
      return merge
    end,

    delete = function(self, pk, options)
      if self.entities[pk_to_s(self.schema, pk)] == nil then
        return nil, "Not found", Errors.NOT_FOUND
      end

      self.entities[pk_to_s(self.schema, pk)] = nil
      return true
    end,

    truncate = function(self)
      self.entities = {}
      return true
    end
  }
end


return Fake
