-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Errors    = require "kong.db.errors"
local Schema    = require "kong.db.schema"
local constants = require "kong.constants"
local workspaces = require "kong.workspaces"
local permissions = require "kong.portal.permissions"
local files = require "kong.db.schema.entities.files"
local sha256_hex = require "kong.tools.sha256".sha256_hex
local file_helpers = require "kong.portal.file_helpers"
local workspace_config = require "kong.portal.workspace_config"


local ws_constants = constants.WORKSPACE_CONFIG
local DEFAULT_WORKSPACE = workspaces.DEFAULT_WORKSPACE



local function is_legacy()
  local workspace = workspaces.get_workspace()
  return workspace_config.retrieve(ws_constants.PORTAL_IS_LEGACY, workspace)
end


local function transform_legacy_fields(entity)
  if entity.auth == "true" then
    entity.auth = true
  elseif entity.auth == "false" then
    entity.auth = false
  end

  return entity
end


local name_cache = {}


-- XXXCORE this module should be changed to rely on ws id and not name
local function get_workspace()
  local ws_id = workspaces.get_workspace_id()
  if not ws_id then
    return DEFAULT_WORKSPACE
  end
  if name_cache[ws_id] then
    return name_cache[ws_id]
  end
  local ws = kong.db.workspaces:select({ id = ws_id })
  if ws then
    name_cache[ws_id] = ws.name
    return ws.name
  end
  return DEFAULT_WORKSPACE
end


local _Files = {}


function _Files:select(file_pk, options)
  if is_legacy() then
    return kong.db.legacy_files:select(file_pk, options)
  end

  local file, err, err_t = self.super.select(self, file_pk, options)
  if not file then
    return nil, err, err_t
  end

  return file, err, err_t
end


function _Files:select_by_path(file_pk, options)
  if is_legacy() then
    return kong.db.legacy_files:select_by_name(file_pk, options)
  end

  local file, err, err_t = self.super.select_by_path(self, file_pk, options)
  if not file then
    return nil, err, err_t
  end

  return file, err, err_t
end


function _Files:each(size, options)
  if is_legacy() then
    return kong.db.legacy_files:each(size, options)
  end

  return self.super.each(self, size, options)
end


-- order for non-legacy file insertions/updates
-- 1. build checksum
-- 2. get path if not included through method
-- 3. validate file
-- 4. set permisions
-- 5. save

function _Files:insert(entity, options)
  if is_legacy() then
    entity = transform_legacy_fields(entity)
    return kong.db.legacy_files:insert(entity, options)
  end

  if next(entity) and entity.contents then
    entity.checksum = entity.checksum or sha256_hex(entity.contents or "")
  end

  local Files = Schema.new(files)
  local ok, err = Files:validate_insert(entity)
  if not ok then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  ok, err  = permissions.set_file_permissions(entity, get_workspace(), nil, true)
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  local inserted, err, err_t = self.super.insert(self, entity, options)
  if not inserted then
    return nil, err, err_t
  end

  return inserted
end


function _Files:upsert(file_pk, entity, options)
  if is_legacy() then
    entity = transform_legacy_fields(entity)
    return kong.db.legacy_files:upsert(file_pk, entity, options)
  end

  if next(entity) and entity.contents then
    entity.checksum = entity.checksum or sha256_hex(entity.contents or "")
  end

  if not entity.path then
    -- err for file not found will be caught by validate
    local file = self.super.select(self, file_pk, options)
    if file then
      entity.path = file.path
    end
  end

  local Files = Schema.new(files)
  local ok, err = Files:validate_upsert(entity)
  if not ok then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  local ok, err = permissions.set_file_permissions(entity, get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  local updated, err, err_t = self.super.upsert(self, file_pk, entity, options)
  if not updated then
    return nil, err, err_t
  end

  return updated
end


function _Files:upsert_by_path(file_pk, entity, options)
  if is_legacy() then
    entity = transform_legacy_fields(entity)
    return kong.db.legacy_files:upsert_by_name(file_pk, entity, options)
  end

  if next(entity) and entity.contents then
    entity.checksum = entity.checksum or sha256_hex(entity.contents or "")
  end

  if not entity.path then
    entity.path = file_pk
  end

  local Files = Schema.new(files)
  local ok, err = Files:validate_upsert(entity)
  if not ok then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  local ok, err = permissions.set_file_permissions(entity, get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  local updated, err, err_t =  self.super.upsert_by_path(self, file_pk, entity, options)
  if not updated then
    return nil, err, err_t
  end
  return updated
end


function _Files:update(file_pk, entity, options)
  if is_legacy() then
    entity = transform_legacy_fields(entity)
    return kong.db.legacy_files:update(file_pk, entity, options)
  end

  if next(entity) and entity.contents then
    entity.checksum = entity.checksum or sha256_hex(entity.contents or "")
  end

  if not entity.path then
    local file = self.super.select(self, file_pk, options)
    if file then
      entity.path = file.path
    end
  end

  local Files = Schema.new(files)
  local ok, err = Files:validate_update(entity)
  if not ok then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  local ok, err = permissions.set_file_permissions(entity, get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  local updated, err, err_t = self.super.update(self, file_pk, entity, options)
  if not updated then
    return nil, err, err_t
  end

  return updated
end


function _Files:update_by_path(file_pk, entity, options)
  if is_legacy() then
    entity = transform_legacy_fields(entity)
    return kong.db.legacy_files:update_by_name(file_pk, entity, options)
  end

  if next(entity) and entity.contents then
    entity.checksum = entity.checksum or sha256_hex(entity.contents or "")
  end

  if not entity.path then
    entity.path = file_pk
  end

  local Files = Schema.new(files)
  local ok, err = Files:validate_update(entity)
  if not ok then
    local err_t = self.errors:schema_violation(err)
    return nil, tostring(err_t), err_t
  end

  ok, err = permissions.set_file_permissions(entity, get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  local updated, err, err_t = self.super.update_by_path(self, file_pk, entity, options)
  if not updated then
    return nil, err, err_t
  end

  return updated
end


function _Files:delete(file_pk, entity, options)
  if is_legacy() then
    return kong.db.legacy_files:delete(file_pk, options)
  end

  local file, err, err_t = self.super.select(self, file_pk)
  if not file then
    return nil, err, err_t
  end

  local ok, err = permissions.delete_file_permissions(file,
                                                      get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  return self.super.delete(self, file_pk, options)
end


function _Files:delete_by_path(file_pk, entity, options)
  if is_legacy() then
    return kong.db.legacy_files:delete_by_name(file_pk, options)
  end

  local file, err, err_t = self.super.select_by_path(self, file_pk)
  if not file then
    return nil, err, err_t
  end

  local ok, err = permissions.delete_file_permissions(file,
                                                      get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  return self.super.delete_by_path(self, file_pk, options)
end


function _Files:select_portal_config()
  local file, err, err_t = self.super.select_by_path(self, 'portal.conf.yaml')
  if not file then
    return nil, err, err_t
  end

  return file
end


function _Files:select_theme_config(theme)
  local file, err, err_t = self.super.select_by_path(self, 'themes/' .. theme .. '/theme.conf.yaml')
  if not file then
    return nil, err, err_t
  end

  return file
end


function _Files:select_file_by_theme(path, theme)
  local file, err, err_t = self.super.select_by_path(self, 'themes/' .. theme .. '/' .. path)
  if not file then
    return nil, err, err_t
  end

  if file_helpers.is_asset(file) then
    file = file_helpers.decode_file(file)
  end

  return file
end

return _Files
