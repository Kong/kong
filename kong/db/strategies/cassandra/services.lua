local cassandra = require "cassandra"


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


return _Services
