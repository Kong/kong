local Errors      = require "kong.db.errors"
local responses   = require "kong.tools.responses"
local utils       = require "kong.tools.utils"
local app_helpers = require "lapis.application"


local escape_uri  = ngx.escape_uri
local null        = ngx.null
local fmt         = string.format
local sub         = string.sub


-- error codes http status codes
local ERRORS_HTTP_CODES = {
  [Errors.codes.INVALID_PRIMARY_KEY]   = 400,
  [Errors.codes.SCHEMA_VIOLATION]      = 400,
  [Errors.codes.PRIMARY_KEY_VIOLATION] = 400,
  [Errors.codes.FOREIGN_KEY_VIOLATION] = 400,
  [Errors.codes.UNIQUE_VIOLATION]      = 409,
  [Errors.codes.NOT_FOUND]             = 404,
  [Errors.codes.INVALID_OFFSET]        = 400,
  [Errors.codes.DATABASE_ERROR]        = 500,
}


local function handle_error(err_t)
  local status = ERRORS_HTTP_CODES[err_t.code]
  if not status or status == 500 then
    return app_helpers.yield_error(err_t)
  end

  responses.send(status, err_t)
end


-- Generates admin api get collection endpoint functions
--
-- Examples:
--
-- /routes
-- /services/:services/routes
--
-- and
--
-- /services
local function get_collection_endpoint(schema_name, entity_name,
                                       parent_schema_name,
                                       parent_entity_has_unique_name)
  if not parent_schema_name then
    return function(self, db, helpers)
      local data, _, err_t, offset = db[schema_name]:page(self.args.size,
                                                          self.args.offset)
      if err_t then
        return handle_error(err_t)
      end

      local next_page = offset and fmt("/%s?offset=%s", schema_name,
                                       escape_uri(offset)) or null

      return helpers.responses.send_HTTP_OK {
        data   = data,
        offset = offset,
        next   = next_page,
      }
    end
  end

  return function(self, db, helpers)
    local id = self.params[parent_schema_name]

    -- TODO: composite key support
    local parent_entity, _, err_t
    if parent_entity_has_unique_name and not utils.is_valid_uuid(id) then
      parent_entity, _, err_t = db[parent_schema_name]:select_by_name(id)

    else
      parent_entity, _, err_t = db[parent_schema_name]:select({ id = id })
    end

    if err_t then
      return handle_error(err_t)
    end

    if not parent_entity then
      return helpers.responses.send_HTTP_NOT_FOUND()
    end

    local entity = db[schema_name]

    -- TODO: composite key support
    local rows, _, err_t, offset = entity["for_" .. entity_name](entity, {
      id = parent_entity.id
    }, self.args.size, self.args.offset)
    if err_t then
      return handle_error(err_t)
    end

    local next_page = offset and fmt("/%s/%s/%s?offset=%s", parent_schema_name,
                                     escape_uri(id), schema_name,
                                     escape_uri(offset)) or null

    return helpers.responses.send_HTTP_OK {
      data   = rows,
      offset = offset,
      next   = next_page,
    }
  end
end


-- Generates admin api post collection endpoint functions
--
-- Examples:
--
-- /routes
-- /services/:services/routes
--
-- and
--
-- /services
local function post_collection_endpoint(schema_name, entity_name,
                                        parent_schema_name,
                                        parent_entity_has_unique_name)
  return function(self, db, helpers)
    if parent_schema_name then
      local id = self.params[parent_schema_name]

      -- TODO: composite key support
      local parent_entity, _, err_t
      if parent_entity_has_unique_name and not utils.is_valid_uuid(id) then
        parent_entity, _, err_t = db[parent_schema_name]:select_by_name(id)

      else
        parent_entity, _, err_t = db[parent_schema_name]:select({ id = id })
      end

      if err_t then
        return handle_error(err_t)
      end

      if not parent_entity then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      -- TODO: composite key support
      self.args.post[entity_name] = { id = parent_entity.id }
    end

    local data, _, err_t = db[schema_name]:insert(self.args.post)
    if err_t then
      return handle_error(err_t)
    end

    return helpers.responses.send_HTTP_CREATED(data)
  end
end


-- Generates admin api get entity endpoint functions
--
-- Examples:
--
-- /routes/:routes
-- /routes/:routes/service
--
-- and
--
-- /services/:services
local function get_entity_endpoint(schema_name, entity_has_unique_name,
                                   entity_name, parent_schema_name,
                                   parent_entity_has_unique_name)
  return function(self, db, helpers)
    local entity, _, err_t

    if not parent_schema_name then
      local id = self.params[schema_name]

      -- TODO: composite key support
      if entity_has_unique_name and not utils.is_valid_uuid(id) then
        entity, _, err_t = db[schema_name]:select_by_name(id)

      else
        entity, _, err_t = db[schema_name]:select({ id = id })
      end

    else
      local id = self.params[parent_schema_name]

      -- TODO: composite key support
      local parent_entity
      if parent_entity_has_unique_name and not utils.is_valid_uuid(id) then
        parent_entity, _, err_t = db[parent_schema_name]:select_by_name(id)

      else
        parent_entity, _, err_t = db[parent_schema_name]:select({ id = id })
      end

      if err_t then
        return handle_error(err_t)
      end

      if not parent_entity or parent_entity[entity_name] == null then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      entity, _, err_t = db[schema_name]:select(parent_entity[entity_name])
    end

    if err_t then
      return handle_error(err_t)
    end

    if not entity then
      return helpers.responses.send_HTTP_NOT_FOUND()
    end

    return helpers.responses.send_HTTP_OK(entity)
  end
end


-- Generates admin api patch entity endpoint functions
--
-- Examples:
--
-- /routes/:routes
-- /routes/:routes/service
--
-- and
--
-- /services/:services
local function patch_entity_endpoint(schema_name, entity_has_unique_name,
                                     entity_name, parent_schema_name,
                                     parent_entity_has_unique_name)
  return function(self, db, helpers)
    local entity, _, err_t

    if not parent_schema_name then
      local id = self.params[schema_name]

      -- TODO: composite key support
      if entity_has_unique_name and not utils.is_valid_uuid(id) then
        entity, _, err_t = db[schema_name]:update_by_name(id, self.args.post)

      else
        entity, _, err_t = db[schema_name]:update({ id = id }, self.args.post)
      end

    else
      local id = self.params[parent_schema_name]

      -- TODO: composite key support
      local parent_entity
      if parent_entity_has_unique_name and not utils.is_valid_uuid(id) then
        parent_entity, _, err_t = db[parent_schema_name]:select_by_name(id)

      else
        parent_entity, _, err_t = db[parent_schema_name]:select({ id = id })
      end

      if err_t then
        return handle_error(err_t)
      end

      if not parent_entity or parent_entity[entity_name] == null then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      entity, _, err_t = db[schema_name]:update(parent_entity[entity_name],
                                                self.args.post)
    end

    if err_t then
      return handle_error(err_t)
    end

    return helpers.responses.send_HTTP_OK(entity)
  end
end


-- Generates admin api delete entity endpoint functions
--
-- Examples:
--
-- /routes/:routes
-- /routes/:routes/service
--
-- and
--
-- /services/:services
local function delete_entity_endpoint(schema_name, entity_has_unique_name,
                                      entity_name, parent_schema_name,
                                      parent_entity_has_unique_name)
  return function(self, db, helpers)
    if not parent_schema_name then
      local id = self.params[schema_name]

      -- TODO: composite key support
      local _, err_t
      if entity_has_unique_name and not utils.is_valid_uuid(id) then
        _, _, err_t = db[schema_name]:delete_by_name(id)

      else
        _, _, err_t = db[schema_name]:delete({ id = id })
      end

      if err_t then
        return handle_error(err_t)
      end

      return helpers.responses.send_HTTP_NO_CONTENT()

    else
      local id = self.params[parent_schema_name]

      -- TODO: composite key support
      local parent_entity, _, err_t
      if parent_entity_has_unique_name and not utils.is_valid_uuid(id) then
        parent_entity, _, err_t = db[parent_schema_name]:select_by_name(id)

      else
        parent_entity, _, err_t = db[parent_schema_name]:select({ id = id })
      end

      if err_t then
        return handle_error(err_t)
      end

      if not parent_entity or parent_entity[entity_name] == null then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return helpers.responses.send_HTTP_METHOD_NOT_ALLOWED()
    end
  end
end


local function generate_collection_endpoints(endpoints, collection_path, ...)
  endpoints[collection_path] = {
    --OPTIONS = method_not_allowed,
    --HEAD    = method_not_allowed,
    GET     = get_collection_endpoint(...),
    POST    = post_collection_endpoint(...),
    --PUT     = method_not_allowed,
    --PATCH   = method_not_allowed,
    --DELETE  = method_not_allowed,
  }
end


local function generate_entity_endpoints(endpoints, entity_path, ...)
  endpoints[entity_path] = {
    --OPTIONS = method_not_allowed,
    --HEAD    = method_not_allowed,
    GET     = get_entity_endpoint(...),
    --POST    = method_not_allowed,
    --PUT     = method_not_allowed,
    PATCH   = patch_entity_endpoint(...),
    DELETE  = delete_entity_endpoint(...),
  }
end


-- Generates admin api endpoint functions
--
-- Examples:
--
-- /routes
-- /routes/:routes
-- /routes/:routes/service
-- /services/:services/routes
--
-- and
--
-- /services
-- /services/:services
local function generate_endpoints(schema, endpoints, prefix)
  local path_prefix
  if prefix then
    if sub(prefix, -1) == "/" then
      path_prefix = prefix

    else
      path_prefix = prefix .. "/"
    end

  else
    path_prefix = "/"
  end

  local schema_name = schema.name
  local collection_path = path_prefix .. schema_name

  -- e.g. /routes
  generate_collection_endpoints(endpoints, collection_path, schema_name)

  local entity_path = fmt("%s/:%s", collection_path, schema_name)
  local entity_name_field = schema.fields.name
  local entity_has_unique_name = entity_name_field and entity_name_field.unique

  -- e.g. /routes/:routes
  generate_entity_endpoints(endpoints, entity_path, schema_name,
                            entity_has_unique_name)

  for foreign_field_name, foreign_field in schema:each_field() do
    if foreign_field.type == "foreign" then
      local foreign_schema      = foreign_field.schema
      local foreign_schema_name = foreign_schema.name

      local foreign_entity_path = fmt("%s/%s", entity_path, foreign_field_name)
      local foreign_entity_name_field = foreign_schema.fields.name
      local foreign_entity_has_unique_name = foreign_entity_name_field and foreign_entity_name_field.unique

      -- e.g. /routes/:routes/service
      generate_entity_endpoints(endpoints, foreign_entity_path,
                                foreign_schema_name,
                                foreign_entity_has_unique_name,
                                foreign_field_name, schema_name,
                                entity_has_unique_name)

      -- e.g. /services/:services/routes
      local foreign_collection_path = fmt("/%s/:%s/%s", foreign_schema_name,
                                          foreign_schema_name, schema_name)

      generate_collection_endpoints(endpoints, foreign_collection_path,
                                    schema_name, foreign_field_name,
                                    foreign_schema_name,
                                    foreign_entity_has_unique_name)
    end
  end

  return endpoints
end


local Endpoints = { handle_error = handle_error }


function Endpoints.new(schema, endpoints, prefix)
  return generate_endpoints(schema, endpoints, prefix)
end


return Endpoints
