local Object = require "classic"

local BaseModel = Object:extend()

function BaseModel:new(db, schema)
  if type(schema.table) ~= "string" then
    error("table must be a string in schema")
  end

  self.db = db
  self.schema = schema
  self.table = self.schema.table
end

function BaseModel:insert(tbl)
  -- TODO validate schema
  return self.db:insert(self.table, tbl)
end

return BaseModel
