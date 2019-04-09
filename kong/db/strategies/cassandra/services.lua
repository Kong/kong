local cassandra = require "cassandra"
local workspaces = require "kong.workspaces"
local rbac = require "kong.rbac"


local fmt = string.format


local _Services = {}


local function select_by_service_id(cluster, table_name, service_id, errors)
  local select_q = fmt("SELECT * FROM %s WHERE service_id = ?",
                       table_name)
  local res   = {}
  local count = 0

  for rows, err in cluster:iterate(select_q, { cassandra.uuid(service_id) }) do
    if err then
      return nil,
             errors:database_error(
               fmt("could not fetch %s for Service: %s", table_name, err))
    end

    for i = 1, #rows do
      count = count + 1
      res[count] = rows[i]
    end
  end

  return res
end

local function delete_cascade(connector, table_name, service_id, errors)
  local entities = select_by_service_id(connector.cluster, table_name, service_id, errors)

  for i = 1, #entities do
    local delete_q = fmt("DELETE from %s WHERE id = ?", table_name)

    local res, err = connector:query(delete_q, {
      cassandra.uuid(entities[i].id)
    }, nil, "write")

    if not res then
      return nil, errors:database_error(
        fmt("could not delete instance of %s associated with Service: %s",
            table_name, err))
    end
  end

  return true
end


function _Services:delete(primary_key)
  local ok, err_t = self.super.delete(self, primary_key)
  if not ok then
    return nil, err_t
  end

  local connector  = self.connector
  local service_id = primary_key.id
  local errors     = self.errors

  local ok1, err1 = delete_cascade(connector, "oauth2_tokens", service_id, errors)
  local ok2, err2 = delete_cascade(connector, "oauth2_authorization_codes", service_id, errors)

  return ok1 and ok2,
         err1 or err2
end

local _Services_ee = {}


local function validate_access(cluster, table_name, service_id, errors, constraints)
  local select_q = fmt("SELECT * FROM %s WHERE service_id = ?",
    table_name)
  local res   = {}
  local count = 0

  for rows, err in cluster:iterate(select_q, { cassandra.uuid(service_id) }) do
    if err then
      return nil, errors:database_error(
        fmt("could not fetch %s for Service: %s", table_name, err))
    end

    for i = 1, #rows do
      if not rbac.validate_entity_operation(rows[i], table_name) then
        return nil, errors:unauthorized_operation({
          username = ngx.ctx.rbac.user.name,
          action = rbac.readable_action(ngx.ctx.rbac.action)
        })
      end
      count = count + 1
      res[count] = rows[i]
    end
  end

  return res
end


local function delete_cascade_ws(connector, table_name, entities, errors, ws)
  if not ws then
    return
  end

  for i = 1, #entities do
    local delete_q = fmt("DELETE from %s WHERE id = ?", table_name)

    local res, err = connector:query(delete_q, {
      cassandra.uuid(entities[i].id)
    }, nil, "write")

    if not res then
      return nil, errors:database_error(
        fmt("could not delete instance of %s associated with Service: %s",
            table_name, err))
    end

    if ws then
      local err = workspaces.delete_entity_relation(table_name, {id = entities[i].id})
      if err then
        return nil, errors:database_error("could not delete " .. table_name ..
                                          " relationship with Workspace: " .. err)
      end

      err = rbac.delete_role_entity_permission(table_name, {id = entities[i].id})
      if err then
        return nil, errors:database_error("could not delete " .. table_name ..
                                          " relationship with Role: " .. err)
      end
    end
  end

  return true
end


function _Services_ee:delete(primary_key, options)
  local ws = workspaces.get_workspaces()[1]
  local connector  = self.connector
  local service_id = primary_key.id
  local errors     = self.errors

  local constraints = workspaces.get_workspaceable_relations()[self.schema.name]

  -- fetch all child entities
  local plugin_list, err1 = validate_access(connector.cluster, "plugins", service_id, errors, constraints)
  local oauth2_tokens_list, err2 = validate_access(connector.cluster, "oauth2_tokens", service_id, errors, constraints)
  local oauth2_codes_list, err3 = validate_access(connector.cluster, "oauth2_authorization_codes", service_id, errors, constraints)
  if err1 or err2 or err3 then
    return nil, err1 or err2 or err3
  end

  if not options or not options.skip_rbac then
    if not rbac.validate_entity_operation(primary_key, self.schema.name) then
      return nil, self.errors:unauthorized_operation({
        username = ngx.ctx.rbac.user.name,
        action = rbac.readable_action(ngx.ctx.rbac.action)
      })
    end
  end

  -- delete parent, also deletes child entities
  local ok, err_t = self.super.delete(self, primary_key)
  if not ok then
    return nil, err_t
  end

  local ok1, err1 = delete_cascade_ws(connector, "plugins", plugin_list, errors, ws)
  local ok2, err2 = delete_cascade_ws(connector, "oauth2_tokens", oauth2_tokens_list, errors, ws)
  local ok3, err3 = delete_cascade_ws(connector, "oauth2_authorization_codes", oauth2_codes_list, errors, ws)

  return ok1 and ok2 and ok3, err1 or err2 or err3, primary_key
end


return _Services_ee or _Services
