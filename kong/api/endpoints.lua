local Errors       = require "kong.db.errors"
local utils        = require "kong.tools.utils"
local arguments    = require "kong.api.arguments"
local app_helpers  = require "lapis.application"


local kong         = kong
local escape_uri   = ngx.escape_uri
local unescape_uri = ngx.unescape_uri
local tonumber     = tonumber
local tostring     = tostring
local select       = select
local pairs        = pairs
local null         = ngx.null
local type         = type
local fmt          = string.format
local concat       = table.concat
local re_match     = ngx.re.match
local split        = utils.split


-- error codes http status codes
local ERRORS_HTTP_CODES = {
  [Errors.codes.INVALID_PRIMARY_KEY]     = 400,
  [Errors.codes.SCHEMA_VIOLATION]        = 400,
  [Errors.codes.PRIMARY_KEY_VIOLATION]   = 400,
  [Errors.codes.FOREIGN_KEY_VIOLATION]   = 400,
  [Errors.codes.UNIQUE_VIOLATION]        = 409,
  [Errors.codes.NOT_FOUND]               = 404,
  [Errors.codes.INVALID_OFFSET]          = 400,
  [Errors.codes.DATABASE_ERROR]          = 500,
  [Errors.codes.INVALID_SIZE]            = 400,
  [Errors.codes.INVALID_UNIQUE]          = 400,
  [Errors.codes.INVALID_OPTIONS]         = 400,
  [Errors.codes.OPERATION_UNSUPPORTED]   = 405,
  [Errors.codes.FOREIGN_KEYS_UNRESOLVED] = 400,
}


local function get_message(default, ...)
  local message
  local n = select("#", ...)
  if n > 0 then
    if n == 1 then
      local arg = select(1, ...)
      if type(arg) == "table" then
        message = arg
      elseif arg ~= nil then
        message = tostring(arg)
      end

    else
      message = {}
      for i = 1, n do
        local arg = select(i, ...)
        message[i] = tostring(arg)
      end
      message = concat(message)
    end
  end

  if not message then
    message = default
  end

  if type(message) == "string" then
    message = { message = message }
  end

  return message
end


local function ok(...)
  return kong.response.exit(200, get_message(nil, ...))
end


local function created(...)
  return kong.response.exit(201, get_message(nil, ...))
end


local function no_content()
  return kong.response.exit(204)
end


local function not_found(...)
  return kong.response.exit(404, get_message("Not found", ...))
end


local function method_not_allowed(...)
  return kong.response.exit(405, get_message("Method not allowed", ...))
end


local function unexpected(...)
  return kong.response.exit(500, get_message("An unexpected error occurred", ...))
end


local function handle_error(err_t)
  if type(err_t) ~= "table" then
    kong.log.err(err_t)
    return unexpected()
  end

  if err_t.strategy then
    err_t.strategy = nil
  end

  local status = ERRORS_HTTP_CODES[err_t.code]
  if not status or status == 500 then
    return app_helpers.yield_error(err_t)
  end

  if err_t.code == Errors.codes.OPERATION_UNSUPPORTED then
    return kong.response.exit(status, err_t)
  end

  return kong.response.exit(status, utils.get_default_exit_body(status, err_t))
end


local function extract_options(args, schema, context)
  local options = {
    nulls = true,
    pagination = {
      page_size     = 100,
      max_page_size = 1000,
    },
  }

  if args and schema and context then
    if schema.ttl == true and args.ttl ~= nil and (context == "insert" or
                                                   context == "update" or
                                                   context == "upsert") then
      options.ttl = args.ttl
      args.ttl = nil
    end

    if schema.fields.tags and args.tags ~= nil and context == "page" then
      local tags = args.tags
      if type(tags) == "table" then
        tags = tags[1]
      end

      if re_match(tags, [=[^([a-zA-Z0-9\.\-\_~]+(?:,|$))+$]=], 'jo') then
        -- 'a,b,c' or 'a'
        options.tags_cond = 'and'
        options.tags = split(tags, ',')
      elseif re_match(tags, [=[^([a-zA-Z0-9\.\-\_~]+(?:/|$))+$]=], 'jo') then
        -- 'a/b/c'
        options.tags_cond = 'or'
        options.tags = split(tags, '/')
      else
        options.tags = tags
        -- not setting tags_cond since we can't determine the cond
        -- will raise an error in db/dao/init.lua:validate_options_value
      end

      args.tags = nil
    end
  end

  return options
end


local function get_page_size(args)
  local size = args.size
  if size ~= nil then
    size = tonumber(size)
    if size == nil then
      return nil, "size must be a number"
    end

    return size
  end
end


local function query_entity(context, self, db, schema, method)
  local is_insert = context == "insert"
  local is_update = context == "update" or context == "upsert"

  local args
  if is_update or is_insert then
    args = self.args.post
  else
    args = self.args.uri
  end

  local opts = extract_options(args, schema, context)
  local dao = db[schema.name]

  if is_insert then
    return dao[method or context](dao, args, opts)
  end

  if context == "page" then
    local size, err = get_page_size(args)
    if err then
      return nil, err, db[schema.name].errors:invalid_size(err)
    end

    if not method then
      return dao[context](dao, size, args.offset, opts)
    end

    return dao[method](dao, self.params[schema.name], size, args.offset, opts)
  end

  local key = self.params[schema.name]
  if key then
    if type(key) ~= "table" then
      if type(key) == "string" then
        key = { id = unescape_uri(key) }
      else
        key = { id = key }
      end
    end

    if key.id and not utils.is_valid_uuid(key.id) then
      local endpoint_key = schema.endpoint_key
      if endpoint_key then
        local field = schema.fields[endpoint_key]
        local inferred_value = arguments.infer_value(key.id, field)
        if is_update then
          return dao[method or context .. "_by_" .. endpoint_key](dao, inferred_value, args, opts)
        end

        return dao[method or context .. "_by_" .. endpoint_key](dao, inferred_value, opts)
      end
    end
  end

  if is_update then
    return dao[method or context](dao, key, args, opts)
  end

  return dao[method or context](dao, key, opts)
end


local function select_entity(...)
  return query_entity("select", ...)
end


local function update_entity(...)
  return query_entity("update", ...)
end


local function upsert_entity(...)
  return query_entity("upsert", ...)
end


local function delete_entity(...)
  return query_entity("delete", ...)
end


local function insert_entity(...)
  return query_entity("insert", ...)
end

local function page_collection(...)
  return query_entity("page", ...)
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
local function get_collection_endpoint(schema, foreign_schema, foreign_field_name, method)
  return not foreign_schema and function(self, db, helpers)
    local next_page_tags = ""

    local args = self.args.uri
    if args.tags then
      next_page_tags = "&tags=" .. (type(args.tags) == "table" and args.tags[1] or args.tags)
    end

    local data, _, err_t, offset = page_collection(self, db, schema, method)
    if err_t then
      return handle_error(err_t)
    end

    local next_page = offset and fmt("/%s?offset=%s%s",
                                     schema.admin_api_name or
                                     schema.name,
                                     escape_uri(offset),
                                     next_page_tags) or null

    return ok {
      data   = data,
      offset = offset,
      next   = next_page,
    }

  end or function(self, db, helpers)
    local foreign_entity, _, err_t = select_entity(self, db, foreign_schema)
    if err_t then
      return handle_error(err_t)
    end

    if not foreign_entity then
      return not_found()
    end

    self.params[schema.name] = foreign_schema:extract_pk_values(foreign_entity)

    local method = method or "page_for_" .. foreign_field_name
    local data, _, err_t, offset = page_collection(self, db, schema, method)
    if err_t then
      return handle_error(err_t)
    end

    local foreign_key = self.params[foreign_schema.name]
    local next_page = offset and fmt("/%s/%s/%s?offset=%s",
                                     foreign_schema.admin_api_name or
                                     foreign_schema.name,
                                     foreign_key,
                                     schema.admin_api_nested_name or
                                     schema.admin_api_name or
                                     schema.name,
                                     escape_uri(offset)) or null

    return ok {
      data   = data,
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
local function post_collection_endpoint(schema, foreign_schema, foreign_field_name, method)
  return function(self, db, helpers, post_process)
    if foreign_schema then
      local foreign_entity, _, err_t = select_entity(self, db, foreign_schema)
      if err_t then
        return handle_error(err_t)
      end

      if not foreign_entity then
        return not_found()
      end

      self.args.post[foreign_field_name] = foreign_schema:extract_pk_values(foreign_entity)
    end

    local entity, _, err_t = insert_entity(self, db, schema, method)
    if err_t then
      return handle_error(err_t)
    end

    if post_process then
      entity, _, err_t = post_process(entity)
      if err_t then
        return handle_error(err_t)
      end
    end

    return created(entity)
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
-- /services/:services/routes/:routes
local function get_entity_endpoint(schema, foreign_schema, foreign_field_name, method, is_foreign_entity_endpoint)
  return function(self, db, helpers)
    local entity, _, err_t
    if foreign_schema then
      entity, _, err_t = select_entity(self, db, schema)
    else
      entity, _, err_t = select_entity(self, db, schema, method)
    end

    if err_t then
      return handle_error(err_t)
    end

    if not entity then
      return not_found()
    end

    if foreign_schema then
      local pk
      if is_foreign_entity_endpoint then
        pk = entity[foreign_field_name]
        if not pk or pk == null then
          return not_found()
        end

        self.params[foreign_schema.name] = pk

      else
        pk = schema:extract_pk_values(entity)
      end

      entity, _, err_t = select_entity(self, db, foreign_schema, method)
      if err_t then
        return handle_error(err_t)
      end

      if not entity then
        return not_found()
      end

      if not is_foreign_entity_endpoint then
        local fk = entity[foreign_field_name]
        if not fk or fk == null then
          return not_found()
        end

        fk = schema:extract_pk_values(fk)
        for k, v in pairs(pk) do
          if fk[k] ~= v then
            return not_found()
          end
        end
      end
    end

    return ok(entity)
  end
end


-- Generates admin api put entity endpoint functions
--
-- Examples:
--
-- /routes/:routes
-- /routes/:routes/service
--
-- and
--
-- /services/:services
-- /services/:services/routes/:routes
local function put_entity_endpoint(schema, foreign_schema, foreign_field_name, method, is_foreign_entity_endpoint)
  return not foreign_schema and function(self, db, helpers)
    local entity, _, err_t = upsert_entity(self, db, schema, method)
    if err_t then
      return handle_error(err_t)
    end

    if not entity then
      return not_found()
    end

    return ok(entity)

  end or function(self, db, helpers)
    local entity, _, err_t = select_entity(self, db, schema)
    if err_t then
      return handle_error(err_t)
    end

    if not entity then
      return not_found()
    end

    local associate

    if is_foreign_entity_endpoint then
      local pk = entity[foreign_field_name]
      if pk and pk ~= null then
        self.params[foreign_schema.name] = pk
      else
        associate = true
        self.params[foreign_schema.name] = utils.uuid()
      end

    else
      self.args.post[foreign_field_name] = schema:extract_pk_values(entity)
    end

    local foreign_entity
    foreign_entity, _, err_t = upsert_entity(self, db, foreign_schema, method)
    if err_t then
      return handle_error(err_t)
    end

    if not foreign_entity then
      return not_found()
    end

    if associate then
      local pk = schema:extract_pk_values(entity)
      local data = {
        [foreign_field_name] = foreign_schema:extract_pk_values(foreign_entity)
      }

      _, _, err_t = db[schema.name]:update(pk, data)
      if err_t then
        return handle_error(err_t)
      end

      --if not entity then
        -- route was deleted after service was created,
        -- so we cannot associate anymore. perhaps not
        -- worth it to handle, the service on the other
        -- hand was updates just fine.
      --end
    end

    return ok(foreign_entity)
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
-- /services/:services/routes/:routes
local function patch_entity_endpoint(schema, foreign_schema, foreign_field_name, method, is_foreign_entity_endpoint)
  return not foreign_schema and function(self, db, helpers)
    local entity, _, err_t = update_entity(self, db, schema, method)
    if err_t then
      return handle_error(err_t)
    end

    if not entity then
      return not_found()
    end

    return ok(entity)

  end or function(self, db, helpers)
    local entity, _, err_t = select_entity(self, db, schema)
    if err_t then
      return handle_error(err_t)
    end

    if not entity then
      return not_found()
    end

    if is_foreign_entity_endpoint then
      local pk = entity[foreign_field_name]
      if not pk or pk == null then
        return not_found()
      end

      self.params[foreign_schema.name] = pk

    else
      if not self.args.post[foreign_field_name] then
        self.args.post[foreign_field_name] = schema:extract_pk_values(entity)
      end

      local pk = schema:extract_pk_values(entity)
      entity, _, err_t = select_entity(self, db, foreign_schema)
      if err_t then
        return handle_error(err_t)
      end

      if not entity then
        return not_found()
      end

      local fk = entity[foreign_field_name]
      if not fk or fk == null then
        return not_found()
      end

      fk = schema:extract_pk_values(fk)
      for k, v in pairs(pk) do
        if fk[k] ~= v then
          return not_found()
        end
      end
    end

    entity, _, err_t = update_entity(self, db, foreign_schema, method)
    if err_t then
      return handle_error(err_t)
    end

    if not entity then
      return not_found()
    end

    return ok(entity)
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
-- /services/:services/routes/:routes
local function delete_entity_endpoint(schema, foreign_schema, foreign_field_name, method, is_foreign_entity_endpoint)
  return not foreign_schema and  function(self, db, helpers)
    local _, _, err_t = delete_entity(self, db, schema, method)
    if err_t then
      return handle_error(err_t)
    end

    return no_content()

  end or function(self, db, helpers)
    local entity, _, err_t = select_entity(self, db, schema)
    if err_t then
      return handle_error(err_t)
    end

    if is_foreign_entity_endpoint then
      local id = entity and entity[foreign_field_name]
      if not id or id == null then
        return not_found()
      end

      return method_not_allowed()
    end

    local pk = schema:extract_pk_values(entity)
    entity, _, err_t = select_entity(self, db, foreign_schema)
    if err_t then
      return handle_error(err_t)
    end

    if not entity then
      return not_found()
    end

    local fk = entity[foreign_field_name]
    if not fk or fk == null then
      return not_found()
    end

    fk = schema:extract_pk_values(fk)
    for k, v in pairs(pk) do
      if fk[k] ~= v then
        return not_found()
      end
    end

    local _, _, err_t = delete_entity(self, db, foreign_schema, method)
    if err_t then
      return handle_error(err_t)
    end

    return no_content()
  end
end

-- Generates admin api collection endpoint functions
--
-- Examples:
--
-- /routes
-- /services/:services/routes
--
-- and
--
-- /services
local function generate_collection_endpoints(endpoints, schema, foreign_schema, foreign_field_name)
  local collection_path
  if foreign_schema then
    collection_path = fmt("/%s/:%s/%s", foreign_schema.admin_api_name or
                                        foreign_schema.name,
                                        foreign_schema.name,
                                        schema.admin_api_nested_name or
                                        schema.admin_api_name or
                                        schema.name)

  else
    collection_path = fmt("/%s", schema.admin_api_name or
                                 schema.name)
  end

  endpoints[collection_path] = {
    schema  = schema,
    methods = {
      --OPTIONS = method_not_allowed,
      --HEAD    = method_not_allowed,
      GET     = get_collection_endpoint(schema, foreign_schema, foreign_field_name),
      POST    = post_collection_endpoint(schema, foreign_schema, foreign_field_name),
      --PUT     = method_not_allowed,
      --PATCH   = method_not_allowed,
      --DELETE  = method_not_allowed,
    },
  }
end


-- Generates admin api entity endpoint functions
--
-- Examples:
--
-- /routes/:routes
-- /routes/:routes/service
--
-- and
--
-- /services/:services
-- /services/:services/routes/:routes
local function generate_entity_endpoints(endpoints, schema, foreign_schema, foreign_field_name, is_foreign_entity_endpoint)
  local entity_path
  if foreign_schema then
    if is_foreign_entity_endpoint then
      entity_path = fmt("/%s/:%s/%s", schema.admin_api_name or
                                      schema.name,
                                      schema.name,
                                      foreign_field_name)
    else
      entity_path = fmt("/%s/:%s/%s/:%s", schema.admin_api_name or
                                          schema.name,
                                          schema.name,
                                          foreign_schema.admin_api_nested_name or
                                          foreign_schema.admin_api_name or
                                          foreign_schema.name,
                                          foreign_schema.name)
    end

  else
    entity_path = fmt("/%s/:%s", schema.admin_api_name or
                                 schema.name,
                                 schema.name)
  end

  endpoints[entity_path] = {
    schema  = foreign_schema or schema,
    methods = {
      --OPTIONS = method_not_allowed,
      --HEAD    = method_not_allowed,
      GET     = get_entity_endpoint(schema, foreign_schema, foreign_field_name, nil, is_foreign_entity_endpoint),
      --POST    = method_not_allowed,
      PUT     = put_entity_endpoint(schema, foreign_schema, foreign_field_name, nil, is_foreign_entity_endpoint),
      PATCH   = patch_entity_endpoint(schema, foreign_schema, foreign_field_name, nil, is_foreign_entity_endpoint),
      DELETE  = delete_entity_endpoint(schema, foreign_schema, foreign_field_name, nil, is_foreign_entity_endpoint),
    },
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
-- /services/:services/routes/:routes
local function generate_endpoints(schema, endpoints)
  -- e.g. /routes
  generate_collection_endpoints(endpoints, schema)

  -- e.g. /routes/:routes
  generate_entity_endpoints(endpoints, schema)

  for foreign_field_name, foreign_field in schema:each_field() do
    if foreign_field.type == "foreign" and not foreign_field.schema.legacy then
      -- e.g. /routes/:routes/service
      generate_entity_endpoints(endpoints, schema, foreign_field.schema, foreign_field_name, true)

      -- e.g. /services/:services/routes
      generate_collection_endpoints(endpoints, schema, foreign_field.schema, foreign_field_name)

      -- e.g. /services/:services/routes/:routes
      generate_entity_endpoints(endpoints, foreign_field.schema, schema, foreign_field_name)
    end
  end

  return endpoints
end


-- A reusable handler for endpoints that are deactivated
-- (e.g. /targets/:targets)
local disable = {
  before = function()
    return not_found()
  end
}


local Endpoints = {
  disable = disable,
  handle_error = handle_error,
  get_page_size = get_page_size,
  extract_options = extract_options,
  select_entity = select_entity,
  update_entity = update_entity,
  upsert_entity = upsert_entity,
  delete_entity = delete_entity,
  insert_entity = insert_entity,
  page_collection = page_collection,
  get_entity_endpoint = get_entity_endpoint,
  put_entity_endpoint = put_entity_endpoint,
  patch_entity_endpoint = patch_entity_endpoint,
  delete_entity_endpoint = delete_entity_endpoint,
  get_collection_endpoint = get_collection_endpoint,
  post_collection_endpoint = post_collection_endpoint,
}


function Endpoints.new(schema, endpoints)
  return generate_endpoints(schema, endpoints)
end


return Endpoints
