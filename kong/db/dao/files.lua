local Errors    = require "kong.db.errors"
local constants = require "kong.constants"
local workspaces = require "kong.workspaces"
local permissions = require "kong.portal.permissions"
local singletons = require "kong.singletons"
local resty_sha256 = require "resty.sha256"
local file_helpers = require "kong.portal.file_helpers"

local ws_constants = constants.WORKSPACE_CONFIG
local DEFAULT_WORKSPACE = workspaces.DEFAULT_WORKSPACE


local CHAR_TO_HEX = {};
for i = 0, 255 do
  local char = string.char(i)
  local hex = string.format("%02x", i)
  CHAR_TO_HEX[char] = hex
end


local function is_legacy()
  local workspace = workspaces.get_workspace()
  return workspaces.retrieve_ws_config(ws_constants.PORTAL_IS_LEGACY, workspace)
end


local function transform_legacy_fields(entity)
  if entity.auth == "true" then
    entity.auth = true
  elseif entity.auth == "false" then
    entity.auth = false
  end

  return entity
end


local function hex_encode(str) -- From prosody's util.hex
  return (str:gsub(".", CHAR_TO_HEX))
end


local function generate_checksum(str)
  local sha256 = resty_sha256:new()
  sha256:update(str or "")
  local digest = sha256:final()
  return hex_encode(digest)
end


local function get_workspace()
  local workspace = ngx.ctx.workspaces and ngx.ctx.workspaces[1]
  if not workspace then
    return DEFAULT_WORKSPACE
  end
  return workspace.name
end


local _Files = {}


function _Files:select(file_pk, options)
  if is_legacy() then
    return singletons.db.legacy_files:select(file_pk, options)
  end

  local file, err, err_t = self.super.select(self, file_pk, options)
  if not file then
    return nil, err, err_t
  end

  return file, err, err_t
end


function _Files:select_by_path(file_pk, options)
  if is_legacy() then
    return singletons.db.legacy_files:select_by_name(file_pk, options)
  end

  local file, err, err_t = self.super.select_by_path(self, file_pk, options)
  if not file then
    return nil, err, err_t
  end

  return file, err, err_t
end


function _Files:select_all(options)
  if is_legacy() then
    return singletons.db.legacy_files:select_all(options)
  end

  local files, err, err_t = self.super.select_all(self, options)
  if not files then
    return nil, err, err_t
  end

  return files
end


function _Files:insert(entity, options)
  if is_legacy() then
    entity = transform_legacy_fields(entity)
    return singletons.db.legacy_files:insert(entity, options)
  end

  if next(entity) and entity.contents then
    entity.checksum = entity.checksum or generate_checksum(entity.contents)
  end

  local inserted, err, err_t = self.super.insert(self, entity, options)
  if not inserted then
    return nil, err, err_t
  end

  local ok, err = permissions.set_file_permissions(inserted, get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  return inserted
end


function _Files:upsert(file_pk, entity, options)
  if is_legacy() then
    entity = transform_legacy_fields(entity)
    return singletons.db.legacy_files:upsert(file_pk, entity, options)
  end

  if next(entity) and entity.contents then
    entity.checksum = entity.checksum or generate_checksum(entity.contents)
  end

  local updated, err, err_t = self.super.upsert(self, file_pk, entity, options)
  if not updated then
    return nil, err, err_t
  end

  local ok, err = permissions.set_file_permissions(updated, get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  return updated
end


function _Files:upsert_by_path(file_pk, entity, options)
  if is_legacy() then
    entity = transform_legacy_fields(entity)
    return singletons.db.legacy_files:upsert_by_name(file_pk, entity, options)
  end

  if next(entity) and entity.contents then
    entity.checksum = entity.checksum or generate_checksum(entity.contents)
  end

  local updated, err, err_t =  self.super.upsert_by_path(self, file_pk, entity, options)
  if not updated then
    return nil, err, err_t
  end

  local ok, err = permissions.set_file_permissions(updated, get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  return updated
end


function _Files:update(file_pk, entity, options)
  if is_legacy() then
    entity = transform_legacy_fields(entity)
    return singletons.db.legacy_files:update(file_pk, entity, options)
  end

  if next(entity) and entity.contents then
    entity.checksum = entity.checksum or generate_checksum(entity.contents)
  end

  local updated, err, err_t = self.super.update(self, file_pk, entity, options)
  if not updated then
    return nil, err, err_t
  end

  local ok, err = permissions.set_file_permissions(updated, get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  return updated
end


function _Files:update_by_path(file_pk, entity, options)
  if is_legacy() then
    entity = transform_legacy_fields(entity)
    return singletons.db.legacy_files:update_by_name(file_pk, entity, options)
  end

  if next(entity) and entity.contents then
    entity.checksum = entity.checksum or generate_checksum(entity.contents)
  end

  local updated, err, err_t = self.super.update_by_path(self, file_pk, entity, options)
  if not updated then
    return nil, err, err_t
  end

  local ok, err = permissions.set_file_permissions(updated, get_workspace())
  if not ok then
    local err_t = Errors:schema_violation({ ["@entity"] = { err } })
    return nil, tostring(err_t), err_t
  end

  return updated
end


function _Files:delete(file_pk, entity, options)
  if is_legacy() then
    return singletons.db.legacy_files:delete(file_pk, options)
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
    return singletons.db.legacy_files:delete_by_name(file_pk, options)
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
