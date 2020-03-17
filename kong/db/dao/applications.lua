local Errors = require "kong.db.errors"
local Schema = require "kong.db.schema"
local pl_stringx   = require "pl.stringx"
local uuid         = require("kong.tools.utils").uuid
local endpoints    = require "kong.api.endpoints"
local enums        = require "kong.enterprise_edition.dao.enums"
local applications = require "kong.db.schema.entities.applications"

local _Applications = {}


local function create_consumer(entity, developer)
  return kong.db.consumers:insert({
    username = developer.id .. "_" ..  entity.name,
    type = enums.CONSUMERS.TYPE.APPLICATION,
  })
end


local function validate_application(entity)
  local temp = setmetatable(entity, {})
  temp.consumer = { id = uuid() }

  return Schema.new(applications):validate_insert(temp)
end


function _Applications:select(application_pk, options)
  local application, err, err_t = self.super.select(self, application_pk, options)
  if not application then
    return nil, err, err_t
  end

  if options and options.with_consumer then
    return application
  end

  return application
end


-- Creates an application, and an associated consumer
function _Applications:insert(entity, options)
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

  local consumer = create_consumer(entity, developer)
  if not consumer then
    local code = Errors.codes.UNIQUE_VIOLATION
    local err = "application insert: application already exists with name: '" .. entity.name .. "'"
    local err_t = { code = code, fields = { name = "application already exists with name: '" .. entity.name .. "'"} }
    return nil, err, err_t
  end

  entity.consumer = { id = consumer.id }

  local application, err, err_t = self.super.insert(self, entity, options)
  if not application then
    kong.db.consumers:delete({ id = consumer.id })
    return nil, err, err_t
  end

  local cred, err, err_t = kong.db.daos["oauth2_credentials"]:insert({
    name = application.name,
    redirect_uris = { application.redirect_uri },
    consumer = application.consumer
  })
  if not cred then
    kong.db.consumers:delete({ id = consumer.id })
    kong.db.applications:delete({ id = application.id })
    return nil, err, err_t
  end

  return application
end


function _Applications:update(application_pk, entity, options)
  entity.consumer = nil
  entity.developer = nil

  if entity.name then
    entity.name = pl_stringx.rstrip(entity.name)
  end

  local application, err, err_t = self.super.select(self, application_pk)
  if not application then
    return nil, err, err_t
  end

  if entity.redirect_uri or entity.name then
    if entity.name then
      local developer = kong.db.developers:select({ id = application.developer.id })
      if developer then
        local ok = kong.db.consumers:update({ id = application.consumer.id }, {
          username = developer.id .. "_" .. entity.name,
        })

        if not ok then
          local code = Errors.codes.UNIQUE_VIOLATION
          local err = "application insert: application already exists with name: '" .. entity.name .. "'"
          local err_t = { code = code, fields = { name = "application already exists with name: '" .. entity.name .. "'"} }
          return nil, err, err_t
        end
      end
    end

    application, err, err_t = self.super.update(self, application_pk, entity, options)
    if not application then
      return nil, err, err_t
    end

    local plugin = kong.db.daos["oauth2_credentials"]
    for row, err in plugin:each_for_consumer({ id = application.consumer.id }) do
      if err then
        return endpoints.handle_error(err)
      end

      plugin:update(
        { id = row.id },
        { redirect_uris = { application.redirect_uri }, name = application.name, }
      )
    end
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
