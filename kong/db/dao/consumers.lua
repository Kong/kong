-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants        = require "kong.constants"
local workspaces       = require "kong.workspaces"
local workspace_config = require "kong.portal.workspace_config"
local new_tab          = require "table.new"

local tostring         = tostring
local null             = ngx.null
local ws_constants     = constants.WORKSPACE_CONFIG
local insert           = table.insert

local get_workspace_id = workspaces.get_workspace_id
local get_workspace = workspaces.get_workspace
local select_workspace_by_id_with_cache = workspaces.select_workspace_by_id_with_cache
local retrieve_workspace_config = workspace_config.retrieve


local check_username_lower_unique
do
  local function is_ignore_case_enabled()
    local admin_auth_type, admin_auth_conf, portal_auth_type, portal_auth_conf
    -- workspace has higher priority than global config
    local workspace
    if kong.cache then
      local ws_id = get_workspace_id()
      workspace = select_workspace_by_id_with_cache(ws_id)
    else
      workspace = get_workspace()
    end

    portal_auth_type = retrieve_workspace_config(ws_constants.PORTAL_AUTH, workspace)
    portal_auth_conf = retrieve_workspace_config(ws_constants.PORTAL_AUTH_CONF, workspace, { decode_json = true })

    local portal_by_username_ignore_case = portal_auth_type == "openid-connect" and
      portal_auth_conf and portal_auth_conf.by_username_ignore_case

    if portal_by_username_ignore_case then
      return true
    end

    if kong.configuration then
      admin_auth_type = kong.configuration.admin_gui_auth
      admin_auth_conf = kong.configuration.admin_gui_auth_conf
    end

    local admin_by_username_ignore_case = admin_auth_type == "openid-connect" and
      admin_auth_conf and admin_auth_conf.by_username_ignore_case

    if admin_by_username_ignore_case then
      return true
    end

    return false
  end

  check_username_lower_unique = function(self, username, primary_key, old_username)
    if not is_ignore_case_enabled() then
      return nil
    end

    -- find existing consumer
    local existing_entity, _
    if primary_key then
      existing_entity, _, _ = self:select(primary_key)
      if not existing_entity then
        return nil
      end

    elseif old_username then
      existing_entity, _, _ = self:select_by_username(old_username)
      if not existing_entity then
        return nil
      end
    end

    -- find consumers that conflict on username_lower
    local consumers, err = self.strategy:select_by_username_ignore_case(username)
    if err then
      return err
    end

    if #consumers > 0 then
      if #consumers == 1 and existing_entity then
        -- if the conflicting consumer is the same as the request, it is not a conflict
        if existing_entity.id ~= consumers[1].id then
          return self.errors:unique_violation({ username_lower = username:lower() })
        end
      else
        return self.errors:unique_violation({ username_lower = username:lower() })
      end
    end

    return nil
  end
end

local function handle_username_lower(self, entity_updates, primary_key, old_username)
  local err_t

  if entity_updates.username_lower then
    err_t = self.errors:schema_violation({ username_lower = 'auto-generated field cannot be set by user' })
    return tostring(err_t), err_t
  end

  if type(entity_updates.username) == 'string' then
    err_t = check_username_lower_unique(self, entity_updates.username, primary_key, old_username)
    if err_t then
      return tostring(err_t), err_t
    end

    entity_updates.username_lower = entity_updates.username:lower()
  elseif entity_updates.username == null then
    -- clear out username_lower if username is ngx.null
    entity_updates.username_lower = null
  end

  return nil
end

local Consumers = {}


function Consumers:page_by_type(_, size, offset, options)
  options = options or {}
  options.search_fields = options.search_fields or {}
  options.search_fields.type = { eq = (options.type or 0) }

  if kong.db.strategy == "postgres" then
    return self:page(size, offset, options)
  end

  -- request fetch all data
  size = size or options.size or 100
  local page, err, err_t, new_offset

  local tab_size = size
  if tab_size > 100 then
    tab_size = 100
  end
  local rows = new_tab(tab_size, 0)

  repeat
    page, err, err_t, new_offset = self:page(size, offset, options)
    if err_t then
      return nil, err, err_t
    end

    for i, row in ipairs(page) do
      local valid_row = row.type == options.search_fields.type.eq
      if valid_row and next(row) then
        insert(rows, row)

        -- current page is full
        if #rows == size then
          -- If we are stopping in the middle of a db page,
          -- our new_offset from self:page is incorrect.
          -- We need to recalculate new_offset from where
          -- we stopped.
          if i ~= #page then
            _, _, _, new_offset = self:page(i, offset, options)
          end

          return rows, nil, nil, new_offset
        end
      end
    end

    offset = new_offset
  until (not offset)

  return rows
end

function Consumers:insert(entity, options)
  local err, err_t = handle_username_lower(self, entity)
  if err_t then
    return nil, err, err_t
  end

  return self.super.insert(self, entity, options)
end

function Consumers:update(primary_key, entity_updates, options)
  local err, err_t = handle_username_lower(self, entity_updates, primary_key)
  if err_t then
    return nil, err, err_t
  end

  return self.super.update(self, primary_key, entity_updates, options)
end

function Consumers:update_by_username(username, entity_updates, options)
  local err, err_t = handle_username_lower(self, entity_updates, nil, username)
  if err_t then
    return nil, err, err_t
  end

  return self.super.update_by_username(self, username, entity_updates, options)
end

function Consumers:upsert(primary_key, entity, options)
  local err, err_t = handle_username_lower(self, entity, primary_key)
  if err_t then
    return nil, err, err_t
  end

  return self.super.upsert(self, primary_key, entity, options)
end

function Consumers:select_by_username_ignore_case(username)
  local consumers, err = self.strategy:select_by_username_ignore_case(username)

  if err then
    return nil, err
  end

  -- sort consumers by created_at date so that the first entry is the oldest
  table.sort(consumers, function(a,b)
    return a.created_at < b.created_at
  end)

  return self:rows_to_entities(consumers), nil
end


return Consumers
