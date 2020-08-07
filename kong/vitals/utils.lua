local enums = require "kong.enterprise_edition.dao.enums"
local _M = {}

-- @param entity: consumer or service DAO
_M.resolve_entity_metadata = function (entity)
  local is_service = not not entity.name
  if is_service then
    return { name = entity.name }
  end
  if entity.type == enums.CONSUMERS.TYPE.APPLICATION then
    return {
      name = "",
      app_id = entity.username:sub(0, entity.username:find("_") - 1),
      app_name = entity.username:sub(entity.username:find("_") + 1)
    }
  end
  return {
    name = entity.username or entity.custom_id,
    app_id = "",
    app_name = "",
  }
end

return _M