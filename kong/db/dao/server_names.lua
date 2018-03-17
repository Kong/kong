local singletons = require "kong.singletons"

-- A "name_list" is an array of server names like { "example.com", "foo.com" }
-- All methods containing "list" on their name act on name lists, not on lists
-- of complete ServerName entities

-- { "a", "b", "c" } - { "a", "c" } = { "b" }
local function list_diff(list1, list2)
  local set2 = {}
  for i=1, #list2 do
    set2[list2[i]] = true
  end

  local diff = {}
  local len = 0
  for i=1, #list1 do
    if not set2[list1[i]] then
      len = len + 1
      diff[len] = list1[i]
    end
  end

  return diff
end


local _ServerNames = {}


-- Truthy if all the names on the list don't exist on the db
function _ServerNames:check_list_is_new(name_list)
  -- when creating a new cert (no cert_id provided):
  -- dont add the certificate or any names if we have an server name conflict
  -- its fairly inefficient that we have to loop twice over the datastore
  -- but no support for OR queries means we gotsta!
  for i=1, #name_list do
    local name = name_list[i]
    local row, err, err_t = singletons.db.server_names:select_by_name(name)
    if err then
      return nil, err, err_t
    end

    if row then
      -- Note: it could be that the name is not associated with any
      -- certificate, but we don't handle this case. (for PostgreSQL
      -- only, as C* requires a cert_id for its partition key).
      local msg   = "Server name already exists: " .. name
      local err_t = self.errors:conflicting_input(msg)
      return nil, tostring(err_t), err_t
    end
  end

  return 1
end


-- Truthy if all the names on the list don't exist on the db or exist but are
-- associated to the given certificate
function _ServerNames:check_list_is_new_or_in_cert(cert_pk, name_list)
  for i=1, #name_list do
    local row, err, err_t = self:select_by_name(name_list[i])
    if err then
      return nil, err, err_t
    end
    if row and row.certificate.id ~= cert_pk.id then
      local msg = "Server Name '" .. row.name ..
                  "' already associated with existing " ..
                  "certificate (" .. row.certificate.id .. ")"
      local err_t = self.errors:conflicting_input(msg)
      return nil, tostring(err_t), err_t
    end
  end

  return 1
end


-- Creates one instance of ServerName for each name in name_list
-- All created instances will be associated to the given certificate
function _ServerNames:insert_list(cert_pk, name_list)
  for _, name in ipairs(name_list) do
    local _, err, err_t = self:insert({
      name         = name,
      certificate  = cert_pk,
    })
    if err then
      return nil, err, err_t
    end
  end

  return 1
end


-- Deletes all server names on the given name list
function _ServerNames:delete_list(name_list)
  local err_list = {}
  local errors_len = 0
  local first_err_t = nil
  for i = 1, #name_list do
    local ok, err, err_t = self:delete_by_name(name_list[i])
    if not ok then
      errors_len = errors_len + 1
      err_list[errors_len] = err
      first_err_t = first_err_t or err_t
    end
  end

  if errors_len > 0 then
    return nil, table.concat(err_list, ","), first_err_t
  end

  return 1
end


-- Returns the name list for a given certificate
function _ServerNames:list_for_certificate(cert_pk)
  local name_list = {}
  local rows, err, err_t = self:for_certificate(cert_pk)
  if err then
    return nil, err, err_t
  end
  for i = 1, #rows do
    name_list[i] = rows[i].name
  end

  table.sort(name_list)
  return name_list
end


-- Replaces the names of a given certificate
-- It does not try to insert server names which are already inserted
-- It does not try to delete server names which don't exist
function _ServerNames:update_list(cert_pk, new_list)
  -- Get the names currently associated to the certificate
  local current_list, err, err_t = self:list_for_certificate(cert_pk)
  if not current_list then
    return nil, err, err_t
  end

  local delete_list = list_diff(current_list, new_list)
  local insert_list = list_diff(new_list, current_list)

  local ok, err, err_t = self:insert_list(cert_pk, insert_list)
  if not ok then
    return nil, err, err_t
  end

  -- ignoring errors here
  -- returning 4xx here risks invalid states and is confusing to the user
  self:delete_list(delete_list)

  return 1
end


return _ServerNames
