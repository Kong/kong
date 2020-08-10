local enums = require "kong.enterprise_edition.dao.enums"
local _M = {}

-- @param[type=table] entity: consumer or service DAO
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

-- Append to vitals stats object.
-- @param[type=table] current_state: vitals "stats" object
-- @param[type=string] index: consumer or service id, or timestamp
-- @param[type=string] status_group: 2XX/4XX/5XX
-- @param[type=number] request_count: total requests
-- @param[type=table] entity_metadata: kong entity name and if application consumer then app_id
_M.append_to_stats = function (current_state, index, status_group, request_count, entity_metadata)
  current_state[index] = current_state[index] or { ["total"] = 0, ["2XX"] = 0, ["4XX"] = 0, ["5XX"] = 0 }
  current_state[index]["total"] = current_state[index]["total"] + request_count
  current_state[index][status_group] = current_state[index][status_group] + request_count
  current_state[index]["name"] = entity_metadata.name
  if not not entity_metadata.app_id then
    current_state[index]["app_id"] = entity_metadata.app_id
    current_state[index]["app_name"] = entity_metadata.app_name
  end
  return current_state
end


return _M