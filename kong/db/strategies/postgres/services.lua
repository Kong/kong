local workspaces = require "kong.workspaces"


local fmt = string.format


local _Services = {}


local function select_by_service_id(self, table_name, service_id, errors)
  local select_q = fmt("SELECT * FROM %s WHERE service_id = '%s'",
                       table_name, service_id)
  local res   = {}
  local count = 0

  for row, err in self.connector:iterate(select_q) do
    if err then
      return nil,
      errors:database_error(
        fmt("could not fetch %s for Service: %s", table_name, err))
    end

    count = count + 1
    res[count] = row
  end

  return res
end

local function delete_cascade(entities, table_name, errors, ws)
  for i = 1, #entities do
    local err = workspaces.delete_entity_relation(table_name, {id = entities[i].id})
    if err then
      return nil, errors:database_error("could not delete " .. table_name ..
                                             " relationship with Workspace: " .. err)
    end
  end

  return true
end


function _Services:delete(primary_key)
  local ws = workspaces.get_workspaces()[1]
  if not ws then
    local ok, err_t = self.super.delete(self, primary_key)
    if not ok then
      return nil, err_t
    end

    return true
  end

  local service_id = primary_key.id
  local errors     = self.errors

  -- fetch all child entities
  local plugin_list = select_by_service_id(self, "plugins", service_id, errors)
  local oauth2_tokens_list = select_by_service_id(self, "oauth2_tokens", service_id, errors)
  local oauth2_codes_list = select_by_service_id(self, "oauth2_authorization_codes", service_id, errors)

  -- delete parent, also deletes child entities
  local ok, err_t = self.super.delete(self, primary_key)
  if not ok then
    return nil, err_t
  end

  -- delete child workspace relationship
  local ok1, err1 = delete_cascade(plugin_list, "plugins", errors, ws)
  local ok2, err2 = delete_cascade(oauth2_tokens_list, "oauth2_tokens", errors, ws)
  local ok3, err3 = delete_cascade(oauth2_codes_list, "oauth2_authorization_codes", errors, ws)

  if err1 or err2 or err3 then
    return false, err1 or err2 or err3
  end

  -- delete workspace relationship
  if ok then
    local err = workspaces.delete_entity_relation("services", {id = service_id})
    if err then
      return nil, self.errors:database_error("could not delete Route relationship " ..
                                             "with Workspace: " .. err)
    end
  end

  return true
end


return _Services
