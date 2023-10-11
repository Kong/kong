-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local Errors = require "kong.db.errors"
local Schema = require "kong.db.schema"
local pl_stringx   = require "pl.stringx"
local uuid         = require("kong.tools.utils").uuid
local enums        = require "kong.enterprise_edition.dao.enums"
local applications = require "kong.db.schema.entities.applications"

local kong = kong
local null = ngx.null
local fmt = string.format
local tostring = tostring


local _Applications = {}


local APP_UNIQUE_ERROR = "application already exists with %s: '%s'"


-- list of attributes that need to mapped from consumers to applications
-- when formatting errors
--
-- key = original key on the consumer error object
-- value = new key as it will appear on an application error object
--
-- e.g.
-- consumer.username -> application.name
-- consumer.custom_id --> application.custom_id
local APP_CONSUMER_ERROR_MAP = {
  username = "name",
  custom_id = "custom_id",
}


-- This table contains application auth strategy specific config
local app_strategies = {
  ["kong-oauth2"] = {
    required_params = { "redirect_uri" },

    post_insert = function(application)
      local oauth2_credential, err, err_t = kong.db.daos["oauth2_credentials"]:insert({
        name = application.name,
        redirect_uris = { application.redirect_uri },
        consumer = application.consumer,
      })

      if not oauth2_credential then
        return nil, err, err_t
      end

      local keyauth_credential, err, err_t = kong.db.daos["keyauth_credentials"]:insert({
        consumer = application.consumer,
        key = oauth2_credential.client_id
      })

      if not keyauth_credential then
        return nil, err, err_t
      end

      return true
    end,

    post_update = function(application)
      local consumer_pk = { id = application.consumer.id }
      local creds = kong.db.daos["oauth2_credentials"]

      for row, err in creds:each_for_consumer(consumer_pk) do
        if err then
          return nil, err
        end

        local ok, err, err_t = creds:update({ id = row.id }, {
          redirect_uris = { application.redirect_uri },
          name = application.name,
        })

        if not ok then
          return nil, err, err_t
        end
      end

      return true
    end,
  },

  ["external-oauth2"] = {
    required_params = { "custom_id" },
    post_insert = function() return true end,
    post_update = function() return true end,
  },
}


local function create_consumer(entity, developer)
  return kong.db.consumers:insert({
    username = developer.id .. "_" ..  entity.name,
    type = enums.CONSUMERS.TYPE.APPLICATION,
    custom_id = entity.custom_id,
  })
end


-- This function checks for the presence of strategy-specific required params
-- Because these params vary by strategy, they are not validated by the schema
local function validate_required_strategy_params(self, op_type, entity, required)
  local missing_val

  -- for updates, we want to check if value is ngx.null
  -- otherwise for insert, we are checking for nil
  if op_type == "update" then
    missing_val = null
  end

  for _, key in ipairs(required) do
    if entity[key] == missing_val then
      local err_t = self.errors:schema_violation({
        [key] = "required field missing"
      })

      return nil, tostring(err_t), err_t
    end
  end

  return true
end


local function validate_application(entity)
  local temp = setmetatable(entity, {})
  temp.consumer = { id = uuid() }

  return Schema.new(applications):validate_insert(temp)
end


local function get_app_auth_strategy()
  local portal_app_auth = kong.configuration.portal_app_auth
  if not portal_app_auth then
    return nil, "portal_app_auth not set"
  end

  local app_auth_strategy = app_strategies[portal_app_auth]
  if not app_auth_strategy then
    return nil, "invalid portal_app_auth strategy"
  end

  return app_auth_strategy
end


-- create new error referring to applications if we encounter
-- a unique violation on consumer 'username' or 'custom_id'
-- otherwise, original error is returned
local function map_app_consumer_errors(self, entity, err, err_t)
  if type(err_t) ~= "table" then
    return nil, err, err_t
  end

  if err_t.code == Errors.codes.UNIQUE_VIOLATION and err_t.fields then
    for orig_key, new_key in pairs(APP_CONSUMER_ERROR_MAP) do
      if err_t.fields[orig_key] then
        local new_err = fmt(APP_UNIQUE_ERROR, new_key, tostring(entity[new_key]))
        local new_err_t = {
          code = err_t.code,
          fields = { [new_key] = new_err },
          name = "unique constraint violation",
          message = new_err,
        }
        return nil, new_err, new_err_t
      end
    end
  end

  -- otherwise, return original error
  return nil, err, err_t
end


function _Applications:select(application_pk, options)
  local application, err, err_t = self.super.select(self, application_pk, options)
  if not application then
    return nil, err, err_t
  end

  return application
end


-- Creates an application, and an associated consumer
function _Applications:insert(entity, options)
  local app_auth_strategy, err = get_app_auth_strategy()
  if not app_auth_strategy then
    return nil, err
  end

  local ok, err, err_t = validate_required_strategy_params(self, "insert",
                                     entity, app_auth_strategy.required_params)
  if not ok then
    return nil, err, err_t
  end

  if entity.name then
    entity.name = pl_stringx.rstrip(entity.name)
  end

  local ok, err, _ = validate_application(entity)
  if not ok then
    local err_t = self.errors:schema_violation(err)
    return nil, err, err_t
  end

  local developer, err, err_t = kong.db.developers:select({id = entity.developer.id})
  if not developer then
    return nil, err, err_t
  end

  local consumer, err, err_t = create_consumer(entity, developer)
  if not consumer then
    return map_app_consumer_errors(self, entity, err, err_t)
  end

  entity.consumer = { id = consumer.id }

  local application, err, err_t = self.super.insert(self, entity, options)
  if not application then
    kong.db.consumers:delete({ id = consumer.id })
    return nil, err, err_t
  end

  local ok, err, err_t = app_auth_strategy.post_insert(application)
  if not ok then
    kong.db.consumers:delete({ id = consumer.id })
    kong.db.applications:delete({ id = application.id })
    return nil, err, err_t
  end

  return application
end


function _Applications:update(application_pk, entity, options)
  entity.consumer = nil
  entity.developer = nil

  local app_auth_strategy, err = get_app_auth_strategy()
  if not app_auth_strategy then
    return nil, err
  end

  local ok, err, err_t = validate_required_strategy_params(self, "update",
                                     entity, app_auth_strategy.required_params)
  if not ok then
    return nil, err, err_t
  end

  local application, err, err_t = self.super.select(self, application_pk)
  if not application then
    return nil, err, err_t
  end

  local consumer_updates = {}

  if entity.name then
    entity.name = pl_stringx.rstrip(entity.name)
    local developer, err, err_t = kong.db.developers:select({
      id = application.developer.id,
    })
    if not developer then
      return nil, err, err_t
    end

    consumer_updates.username = developer.id .. "_" .. entity.name
  end

  if entity.custom_id then
    consumer_updates.custom_id = entity.custom_id
  end

  if next(consumer_updates) then
    local ok, err, err_t = kong.db.consumers:update({
      id = application.consumer.id
    }, consumer_updates)
    if not ok then
      return map_app_consumer_errors(self, entity, err, err_t)
    end
  end

  application, err, err_t = self.super.update(self, application_pk, entity,
                                                                      options)
  if not application then
    return nil, err, err_t
  end

  local ok, err, err_t = app_auth_strategy.post_update(application)
  if not ok then
    return nil, err, err_t
  end

  return application
end


function _Applications:delete(application_pk, options)
  local application, err, err_t = self.super.select(self, application_pk)
  if not application then
    return nil, err, err_t
  end

  for row, err in kong.db.application_instances:each_for_application({ id = application.id }) do
    if err then
      return nil, err
    end

    local ok, err, err_t = kong.db.application_instances:delete({ id = row.id })
    if not ok then
      return ok, err, err_t
    end
  end

  local ok, err, err_t = self.super.delete(self, application_pk, options)
  if not ok then
    return nil, err, err_t
  end

  return kong.db.consumers:delete({ id = application.consumer.id })
end


return _Applications
