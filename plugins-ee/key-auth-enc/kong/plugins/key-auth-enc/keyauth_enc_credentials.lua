-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Errors = require "kong.db.errors"
local sha256_hex = require "kong.tools.sha256".sha256_hex
local str = require "resty.string"
local workspaces = require "kong.workspaces"

local _M = {}


local function reduce_ids(id_rows)
  local ids = {}

  for _, row in ipairs(id_rows) do
    table.insert(ids, row.id)
  end

  return ids
end


function _M:key_ident(cred, sha1_fallback)
  if sha1_fallback then
    -- falling back to sha1 identifier (read-only)
    return string.sub(str.to_hex(ngx.sha1_bin(cred.key)), 1, 5)
  end

  local cred_key, err = sha256_hex(tostring(cred.key))
  if not cred_key then
    return nil, err
  end

  return cred_key:sub(1, 5)
end


function _M:key_ident_cache_key(cred, sha1_fallback)
  local ident, err = self:key_ident(cred, sha1_fallback)
  if not ident then
    return nil, err
  end

  local ws_id = workspaces.get_workspace_id()
  return "keyauth_credentials_ident:" .. ident .. ":" .. ws_id
end


function _M:validate_unique(cred)
  if not cred.key then
    return nil, Errors:schema_violation({ "missing credential key" })
  end

  local ident, err = self:key_ident(cred)
  if not ident then
    return nil, err
  end

  local ids, err = self.strategy:select_ids_by_ident(ident)
  if not ids or #ids == 0 then
    ident = self:key_ident(cred, true)
    ids, err = self.strategy:select_ids_by_ident(ident)
  end
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
  -- XXX Here be dragons. This works for hybrid because key in declarative
  -- is non encrypted
  if self.strategy.off then
    return self.strategy:select_ids_by_key(key)
  else
    local ident, err = self:key_ident({ key = key })
    if not ident then
      return nil, err, err
    end

    local ids, err = self.strategy:select_ids_by_ident(ident)
    if not ids or #ids == 0 then
      ident = self:key_ident({ key = key }, true)
      ids, err = self.strategy:select_ids_by_ident(ident)
    end
    if not ids then
      return nil, err, err
    end

    return ids
  end
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


function _M:insert(in_cred, options)
  local cred, err = self.schema:process_auto_fields(in_cred, "insert", options)
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

  local ident, err = self:key_ident({ key = row.key })
  if not ident then
    return nil, err, err
  end

  local ok, err = self.strategy:insert_ident(row, ident)
  if not ok then
    return nil, err, err
  end

  return row
end


function _M:update(cred_pk, in_cred, options)
  local cred, err = self.schema:process_auto_fields(in_cred, "update", options)
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

  local ident, err = self:key_ident(row)
  if not ident then
    return nil, err, err
  end

  local ok, err = self.strategy:insert_ident(row, ident)
  if not ok then
    return nil, err, err
  end

  return row
end


function _M:upsert(cred_pk, in_cred, options)
  local cred, err = self.schema:process_auto_fields(in_cred, "upsert", options)
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

  local ident, err = self:key_ident(row)
  if not ident then
    return nil, err, err
  end

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
