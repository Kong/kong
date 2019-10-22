local cjson = require "cjson"
local Set   = require "pl.Set"


local setmetatable = setmetatable
local tostring = tostring
local ipairs = ipairs
local table = table


local function invalidate_cache(self, old_entity, err, err_t)
  if err then
    return nil, err, err_t
  end
  if old_entity then
    self:post_crud_event("update", old_entity)
  end
end


local _SNIs = {}


-- Truthy if all the names on the list don't exist on the db or exist but are
-- associated to the given certificate
-- if the cert id is nil, all encountered snis will return an error
function _SNIs:check_list_is_new(name_list, valid_cert_id)
  for i=1, #name_list do
    local name = name_list[i]
    local row, err, err_t = self:select_by_name(name)
    if err then
      return nil, err, err_t
    end
    if row and row.certificate.id ~= valid_cert_id then
      local msg = name ..
                  " already associated with existing " ..
                  "certificate '" .. row.certificate.id .. "'"
      local err_t = self.errors:schema_violation({ snis = msg })
      return nil, tostring(err_t), err_t
    end
  end

  return true
end


-- Creates one instance of SNI for each name in name_list
-- All created instances will be associated to the given certificate
function _SNIs:insert_list(cert_pk, name_list)
  for _, name in ipairs(name_list) do
    local _, err, err_t = self:insert({
      name         = name,
      certificate  = cert_pk,
    })
    if err then
      return nil, err, err_t
    end
  end

  return true
end


-- Deletes all SNIs on the given name list
function _SNIs:delete_list(name_list)
  local err_list = {}
  local errors_len = 0
  local first_err_t
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

  return true
end


-- Returns the name list for a given certificate
function _SNIs:list_for_certificate(cert_pk, options)
  local name_list = setmetatable({}, cjson.array_mt)

  for sni, err, err_t in self:each_for_certificate(cert_pk, nil, options) do
    if err then
      return nil, err, err_t
    end

    table.insert(name_list, sni.name)
  end

  table.sort(name_list)

  return name_list
end


-- Replaces the names of a given certificate
-- It does not try to insert SNIs which are already inserted
-- It does not try to delete SNIs which don't exist
function _SNIs:update_list(cert_pk, new_list)
  -- Get the names currently associated to the certificate
  local current_list, err, err_t = self:list_for_certificate(cert_pk)
  if not current_list then
    return nil, err, err_t
  end

  local delete_list = Set.values(Set(current_list) - Set(new_list))
  local insert_list = Set.values(Set(new_list) - Set(current_list))

  local ok, err, err_t = self:insert_list(cert_pk, insert_list)
  if not ok then
    return nil, err, err_t
  end

  -- ignoring errors here
  -- returning 4xx here risks invalid states and is confusing to the user
  self:delete_list(delete_list)

  return true
end


-- invalidates the *old* name when updating it to a new name
function _SNIs:update(pk, entity, options)
  local _, err, err_t = invalidate_cache(self, self:select(pk))
  if err then
    return nil, err, err_t
  end

  return self.super.update(self, pk, entity, options)
end


-- invalidates the *old* name when updating it to a new name
function _SNIs:update_by_name(name, entity, options)
  local _, err, err_t = invalidate_cache(self, self:select_by_name(name))
  if err then
    return nil, err, err_t
  end

  return self.super.update_by_name(self, name, entity, options)
end


-- invalidates the *old* name when updating it to a new name
function _SNIs:upsert(pk, entity, options)
  local _, err, err_t = invalidate_cache(self, self:select(pk))
  if err then
    return nil, err, err_t
  end

  return self.super.upsert(self, pk, entity, options)
end


-- invalidates the *old* name when updating it to a new name
function _SNIs:upsert_by_name(name, entity, options)
  local _, err, err_t = invalidate_cache(self, self:select_by_name(name))
  if err then
    return nil, err, err_t
  end

  return self.super.upsert_by_name(self, name, entity, options)
end


return _SNIs
