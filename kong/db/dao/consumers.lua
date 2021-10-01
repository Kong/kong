-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson            = require "cjson.safe"
local singletons       = require "kong.singletons"
local constants        = require "kong.constants"
local workspaces       = require "kong.workspaces"
local workspace_config = require "kong.portal.workspace_config"

local tostring         = tostring
local ws_constants     = constants.WORKSPACE_CONFIG

local invalidate_consumer_cache = function(self, entity, options)
  -- skip next lines in some tests where kong.cache is not available
  if not kong.cache then
    return
  end

  local fields = { "custom_id", "username", "username_lower" }
  for _, field in ipairs(fields) do
    if entity[field] then
      local cache_key = self:cache_key(field, entity[field])
      if options and options.no_broadcast_crud_event then
        kong.cache:invalidate_local(cache_key)
      else
        kong.cache:invalidate(cache_key)
      end
    end
  end
end

local check_username_lower_unique = function(self, entity, options)
  local workspace = workspaces.get_workspace()

  local admin_auth_type, admin_auth_conf, portal_auth_type, portal_auth_conf, err

  if singletons.configuration then
    admin_auth_type = singletons.configuration.admin_gui_auth
    admin_auth_conf = singletons.configuration.admin_gui_auth_conf
  end
  portal_auth_type = workspace_config.retrieve(ws_constants.PORTAL_AUTH, workspace)
  portal_auth_conf = workspace_config.retrieve(ws_constants.PORTAL_AUTH_CONF, workspace)

  if type(portal_auth_conf) == 'string' then
    portal_auth_conf, err = cjson.decode(portal_auth_conf)
    if err then
      return err
    end
  end

  local portal_by_username_ignore_case = portal_auth_type == "openid-connect" and
    portal_auth_conf and portal_auth_conf.by_username_ignore_case

  local admin_by_username_ignore_case = admin_auth_type == "openid-connect" and
    admin_auth_conf and admin_auth_conf.by_username_ignore_case

  if not portal_by_username_ignore_case and not admin_by_username_ignore_case then
    -- only check for unique_violation on username_lower if by_username_ignore_case
    -- is used in portal or admin OIDC conf
    return nil
  end

  if err then
    return err
  end

  return nil
end

local handle_username_lower = function(self, entity, options)
  local err_t

  if entity.username_lower then
    err_t = self.errors:schema_violation({ username_lower = 'auto-generated field cannot be set by user' })
    return nil, tostring(err_t), err_t
  end

  if type(entity.username) == 'string' then
    entity.username_lower = entity.username:lower()
  end

  err_t = check_username_lower_unique(self, entity, options)
  if err_t then
    return nil, tostring(err_t), err_t
  end

  return true
end

local Consumers = {}


function Consumers:page_by_type(_, size, offset, options)
  options = options or {}
  options.type = options.type or 0

  size = size or options.size or 100

  local count = 1
  local MAX_ITERATIONS = 5
  local r, err, err_t, next_offset = self:page(size, offset, options)
  if err_t then
    return nil, err, err_t
  end

  local rows = {}
  for _, c in ipairs(r) do
    if c.type == options.type then
      table.insert(rows, c)
    end
  end

  while count < MAX_ITERATIONS and #rows < size and next_offset do
    r, err, err_t, next_offset = self:page(size - #rows, next_offset, options)
    if err_t then
      return nil, err, err_t
    end
    for _, c in ipairs(r) do
      if c.type == options.type then
        table.insert(rows, c)
      end
    end
    count = count + 1
  end

  return rows, nil, nil, next_offset
end

function Consumers:delete(primary_key, options)
  local consumer = self:select(primary_key)
  if consumer then
    invalidate_consumer_cache(self, consumer, options)
  end

  return self.super.delete(self, primary_key, options)
end

function Consumers:insert(entity, options)
  local _, err, err_t = handle_username_lower(self, entity, options)
  if err_t then
    return nil, err, err_t
  end

  invalidate_consumer_cache(self, entity, options)

  return self.super.insert(self, entity, options)
end

function Consumers:update(primary_key, entity, options)
  local _, err, err_t = handle_username_lower(self, entity, options)
  if err_t then
    return nil, err, err_t
  end

  local old_consumer = self:select(primary_key)
  if old_consumer then
    invalidate_consumer_cache(self, old_consumer, options)
  end

  return self.super.update(self, primary_key, entity, options)
end

function Consumers:update_by_username(username, entity, options)
  local _, err, err_t = handle_username_lower(self, entity, options)
  if err_t then
    return nil, err, err_t
  end

  local old_consumer = self:select_by_username(username)
  if old_consumer then
    invalidate_consumer_cache(self, old_consumer, options)
  end

  return self.super.update_by_username(self, username, entity, options)
end

function Consumers:upsert(primary_key, entity, options)
  local _, err, err_t = handle_username_lower(self, entity, options)
  if err_t then
    return nil, err, err_t
  end

  local old_consumer = self:select(primary_key)
  if old_consumer then
    invalidate_consumer_cache(self, old_consumer, options)
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
