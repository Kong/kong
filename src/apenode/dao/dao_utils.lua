local cjson = require "cjson"

local _M = {}

function _M.serialize(schema, entity)
  if entity then
    for k,v in pairs(schema) do
      if entity[k] and v.type == "table" then
        entity[k] = cjson.encode(entity[k])
      end
    end
  end
  return entity
end

function _M.deserialize(schema, entity)
  if entity then
    for k,v in pairs(schema) do
      if entity[k] and v.type == "table" then
        entity[k] = cjson.decode(entity[k])
      end
    end
  end
  return entity
end

return _M
