local Errors = require "kong.db.errors"


local _M = {}


local function reduce_ids(id_rows)
  local ids = {}

  for _, row in ipairs(id_rows) do
    table.insert(ids, row.id)
  end

  return ids
end


function _M:key_ident(cred)
  local str = require "resty.string"

  return string.sub(str.to_hex(ngx.sha1_bin(cred.key)), 1, 5)
end


function _M:key_ident_cache_key(cred)
  return "keyauth_credentials_ident:" .. self:key_ident(cred)
end


function _M:validate_unique(cred)
  if not cred.key then
    return nil, Errors:schema_violation({ "missing credential key" })
  end

  local ident = self:key_ident(cred)

  local ids, err = self.strategy:select_ids_by_ident(ident)
  if not ids then
    return nil, err
  end

  for _, id in ipairs(reduce_ids(ids)) do
    local row, err = self:select({ id = id })
    if err then
      return nil, err
    end

    if row and row.key == cred.key then
      return nil, Errors:unique_violation({ key = cred })
    end
  end

  return true
end


function _M:select_ids_by_ident(key)
  local ident = self:key_ident({ key = key })

  local ids, err = self.strategy:select_ids_by_ident(ident)
  if not ids then
    return nil, err, err
  end

  return ids
end


function _M:validate_ident(ids, key)
  for _, id in ipairs(reduce_ids(ids)) do
    local row, err = self:select({ id = id })
    if err then
      return nil, err, err
    end

    -- idents matched, check
    -- note we did a raw query not respecting workspaces to fetch the idents
    -- so there may not be a row here from :select(), despite an ident match
    if row and row.key == key then
      return row
    end
  end
end


function _M:insert(_cred, options)
  local cred, err = self.schema:process_auto_fields(_cred, "insert", options)
  if not cred then
    return nil, Errors:schema_violation(err)
  end

  local ok, err_t = self:validate_unique(cred)
  if not ok then
    return nil, tostring(err_t), err_t
  end

  local row, err, err_t = self.super.insert(self, cred, options)
  if not row then
    return nil, err, err_t
  end

  local ident = self:key_ident({ key = row.key })

  local ok, err = self.strategy:insert_ident(row, ident)
  if not ok then
    return nil, err, err
  end

  return row
end


function _M:update(cred_pk, _cred, options)
  local cred, err = self.schema:process_auto_fields(_cred, "update", options)
  if not cred then
    return nil, Errors:schema_violation(err)
  end

  local ok, err_t = self:validate_unique(cred)
  if not ok then
    return nil, tostring(err_t), err_t
  end

  local row, err, err_t = self.super.update(self, cred_pk, cred, options)
  if not row then
    return nil, err, err_t
  end

  local ident = self:key_ident(row)

  local ok, err = self.strategy:insert_ident(row, ident)
  if not ok then
    return nil, err, err
  end

  return row
end


function _M:upsert(cred_pk, _cred, options)
  local cred, err = self.schema:process_auto_fields(_cred, "upsert", options)
  if not cred then
    return nil, Errors:schema_violation(err)
  end

  local ok, err_t = self:validate_unique(cred)
  if not ok then
    return nil, tostring(err_t), err_t
  end

  local row, err, err_t = self.super.upsert(self, cred_pk, cred, options)
  if not row then
    return nil, err, err_t
  end

  local ident = self:key_ident(row)

  local ok, err = self.strategy:insert_ident(row, ident)
  if not ok then
    return nil, err, err
  end

  return row
end


function _M:post_crud_event(operation, entity, old_entity)
  if old_entity then
    old_entity.key = require("kong.keyring").decrypt(old_entity.key)
  end

  return self.super.post_crud_event(self, operation, entity, old_entity)
end


return _M
