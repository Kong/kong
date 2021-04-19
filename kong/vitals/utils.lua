-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local enums = require "kong.enterprise_edition.dao.enums"
local null  = ngx.null
local _M = {}

local duration_to_interval = {
  [1] = "seconds",
  [60] = "minutes",
  [3600] = "hours",
  [86400] = "days",
  [604800] = "weeks",
}
_M.duration_to_interval = duration_to_interval

local interval_to_duration = {
  seconds = 1,
  minutes = 60,
  hours = 3600,
  days = 86400,
  weeks = 604800,
}
_M.interval_to_duration = interval_to_duration

-- Parses kong service or consumer DAO for name and in the case of consumer,
-- application name and id.
-- @param[type=table] entity: consumer or service DAO
local function resolve_entity_metadata(entity)
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
_M.resolve_entity_metadata = resolve_entity_metadata

-- Append to vitals stats object.
-- @param[type=table] current_state: vitals "stats" object
-- @param[type=string] index: consumer or service id, or timestamp
-- @param[type=string] status_group: 2XX/4XX/5XX
-- @param[type=number] request_count: total requests
-- @param[type=table] entity_metadata: kong entity name and if application consumer then app_id
local function append_to_stats(current_state, index, status_group, request_count, entity_metadata)
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
_M.append_to_stats = append_to_stats

-- Fetches kong service or consumer names from db
-- @param[type=table] entity: consumer or service DAO
-- @param[type=nullable-string] entity_id: UUID or nil, signifies how each row is indexed
local function get_entity_metadata(entity, entity_id)
  local entities = {}
  local plural_entity = entity .. 's'
  local has_entity_id = entity_id ~= nil
  if has_entity_id then
    local row = kong.db[plural_entity]:select({ id = entity_id }, { workspace = null })
    local has_entity_in_db = row ~= nil
    if has_entity_in_db then entities[row.id] = resolve_entity_metadata(row) end
  else
    for row in kong.db[plural_entity]:each(nil, { workspace = null }) do
      local has_entity_in_db = row ~= nil
      if has_entity_in_db then entities[row.id] = resolve_entity_metadata(row) end
    end
  end
  return entities
end
_M.get_entity_metadata = get_entity_metadata

return _M
