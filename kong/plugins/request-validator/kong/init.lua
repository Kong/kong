local cjson = require "cjson.safe"
local Entity = require "kong.db.schema.entity"
local NewErrors = require "kong.db.errors"
local metaschema = require "kong.plugins.request-validator.kong.metaschema"


local _M = {}

local function get_schema(fields)
  if type(fields) == "string" then
    local t, err = cjson.decode(fields)
    if not t then
      return nil, "failed decoding schema: " .. tostring(err)
    end
    fields = t
  end

  if type(fields) ~= "table" then
    return nil, "expected string or table, got: " ..  type(fields)
  end

  return {
    name = "name",
    primary_key = {"pk"},
    fields = fields,
  }
end


function _M.generate(plugin_conf)
  local schema, err = get_schema(plugin_conf.body_schema)
  if err then
    return false, err
  end

  local entity, err = Entity.new(schema)
  if err then
    return false, err
  end

  return function(body)
           return entity:validate(body)
         end
end


function _M.validate(entity)
  local schema, err = get_schema(entity.config.body_schema)
  if err then
    return false, err
  end

  -- validate against metaschema
  local ok
  ok, err = metaschema:validate(schema)
  if not ok then
    return false, NewErrors:schema_violation(err)
  end

  return true
end

return _M
