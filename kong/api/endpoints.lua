local escape_uri = ngx.escape_uri
local concat     = table.concat
local null       = ngx.null
local find       = string.find
local fmt        = string.format
local sub        = string.sub


-- Generates admin api get collection endpoint functions
--
-- Examples:
--
-- /routes
-- /services/<service_id>/routes
--
-- and
--
-- /services
local function get_collection_endpoint(schema_name, entity_name, parent_schema_name)
  if not parent_schema_name then
    return function(self, db, helpers)
      local data, _, err_t, offset = db[schema_name]:page(
        self.args.size,
        self.args.offset)

      if err_t then
        return helpers.yield_error(err_t)
      end

      local next_page = offset and fmt("/%s?offset=%s", schema_name, escape_uri(offset)) or null

      return helpers.responses.send_HTTP_OK {
        data   = data,
        offset = offset,
        next   = next_page,
      }
    end
  end

  return function(self, db, helpers)
    -- TODO: composite key support
    local fk = { id = self.params[parent_schema_name] }

    local parent_entity, _, err_t = db[parent_schema_name]:select(fk)
    if err_t then
      return helpers.yield_error(err_t)
    end

    if not parent_entity then
      return helpers.responses.send_HTTP_NOT_FOUND()
    end

    local entity = db[schema_name]

    local rows, _, err_t, offset = entity["for_" .. entity_name](
      entity,
      fk,
      self.args.size,
      self.args.offset)

    if err_t then
      return helpers.yield_error(err_t)
    end

    local next_page = offset and fmt("/%s/%s/%s?offset=%s",
      parent_schema_name, escape_uri(fk.id), schema_name, escape_uri(offset)) or null

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
-- /services/<service_id>/routes
--
-- and
--
-- /services
local function post_collection_endpoint(schema_name, entity_name, parent_schema_name)
  return function(self, db, helpers)
    if parent_schema_name then
      -- TODO: composite key support
      local fk = { id = self.params[parent_schema_name] }

      local parent_entity, _, err_t = db[parent_schema_name]:select(fk)
      if err_t then
        return helpers.yield_error(err_t)
      end

      if not parent_entity then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.args.post[entity_name] = fk
    end

    local data, _, err_t = db[schema_name]:insert(self.args.post)
    if err_t then
      return helpers.yield_error(err_t)
    end

    return helpers.responses.send_HTTP_CREATED(data)
  end
end

-- Generates admin api get entity endpoint functions
--
-- Examples:
--
-- /routes/<route-id>
-- /routes/<route-id>/service
--
-- and
--
-- /services/<service_id>
local function get_entity_endpoint(schema_name, entity_name, parent_schema_name)
  return function(self, db, helpers)
    local pk

    if not parent_schema_name then
      pk = { id = self.params[schema_name] }

    else
      -- TODO: composite key support
      local fk = { id = self.params[parent_schema_name] }

      local parent_entity, _, err_t = db[parent_schema_name]:select(fk)
      if err_t then
        return helpers.yield_error(err_t)
      end

      if not parent_entity or parent_entity[entity_name] == null then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      pk = parent_entity[entity_name]
    end

    local entity, _, err_t = db[schema_name]:select(pk)
    if err_t then
      return helpers.yield_error(err_t)
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
-- /routes/<route-id>
-- /routes/<route-id>/service
--
-- and
--
-- /services/<service_id>
local function patch_entity_endpoint(schema_name, entity_name, parent_schema_name)
  return function(self, db, helpers)
    local pk

    if not parent_schema_name then
      pk = { id = self.params[schema_name] }

    else
      -- TODO: composite key support
      local fk = { id = self.params[parent_schema_name] }

      local parent_entity, _, err_t = db[parent_schema_name]:select(fk)
      if err_t then
        return helpers.yield_error(err_t)
      end

      if not parent_entity or parent_entity[entity_name] == null then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      pk = parent_entity[entity_name]
    end

    local entity, _, err_t = db[schema_name]:update(pk, self.args.post)
    if err_t then
      return helpers.yield_error(err_t)
    end

    return helpers.responses.send_HTTP_OK(entity)
  end
end


-- Generates admin api delete entity endpoint functions
--
-- Examples:
--
-- /routes/<route-id>
-- /routes/<route-id>/service
--
-- and
--
-- /services/<service_id>
local function delete_entity_endpoint(schema_name, entity_name, parent_schema_name)
  return function(self, db, helpers)
    local pk

    if not parent_schema_name then
      pk = { id = self.params[schema_name] }

    else
      -- TODO: composite key support
      local fk = { id = self.params[parent_schema_name] }

      local parent_entity, _, err_t = db[parent_schema_name]:select(fk)
      if err_t then
        return helpers.yield_error(err_t)
      end

      if not parent_entity or parent_entity[entity_name] == null then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return helpers.responses.send_HTTP_METHOD_NOT_ALLOWED()
    end

    local _, _, err_t = db[schema_name]:delete(pk)
    if err_t then
      return helpers.yield_error(err_t)
    end

    return helpers.responses.send_HTTP_NO_CONTENT()
  end
end


local function generate_collection_endpoints(endpoints, collection_path, ...)
  endpoints[collection_path] = {
    --OPTIONS =     method_not_allowed,
    --HEAD    =     method_not_allowed,
    GET     =    get_collection_endpoint(...),
    POST    =   post_collection_endpoint(...),
    --PUT     =     method_not_allowed,
    --PATCH   =     method_not_allowed,
    --DELETE  =     method_not_allowed,
  }
end


local function generate_entity_endpoints(endpoints, entity_path, ...)
  endpoints[entity_path] = {
    --OPTIONS =     method_not_allowed,
    --HEAD    =     method_not_allowed,
    GET     =    get_entity_endpoint(...),
    --POST    =     method_not_allowed,
    --PUT     =     method_not_allowed,
    PATCH   =  patch_entity_endpoint(...),
    DELETE  = delete_entity_endpoint(...),
  }
end


-- Generates admin api endpoint functions
--
-- Examples:
--
-- /routes
-- /routes/<route-id>
-- /routes/<route-id>/service
-- /services/<service_id>/routes
--
-- and
--
-- /services
-- /services/<service_id>
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

  local collection_key = fmt("/%s/", schema_name)

  if find(path_prefix, collection_key, nil, true) then
    return endpoints
  end

  local collection_path = concat {
    path_prefix,
    schema_name,
  }

  generate_collection_endpoints(endpoints, collection_path, schema_name)

  local entity_path = fmt("%s/:%s", collection_path, schema_name)

  generate_entity_endpoints(endpoints, entity_path, schema_name)

  for foreign_field_name, foreign_field in schema:each_field() do
    if foreign_field.type == "foreign" then
      local foreign_schema_name = foreign_field.schema.name

      local foreign_entity_path = fmt("%s/%s", entity_path, foreign_field_name)
      generate_entity_endpoints(
        endpoints,
        foreign_entity_path,
        foreign_schema_name,
        foreign_field_name,
        schema_name)

      local foreign_collection_path = fmt("/%s/:%s/%s", foreign_schema_name, foreign_schema_name, schema_name)
      generate_collection_endpoints(
        endpoints,
        foreign_collection_path,
        schema_name,
        foreign_field_name,
        foreign_schema_name)
    end
  end

  return endpoints
end


local Endpoints = {}


function Endpoints.new(schema, endpoints, prefix)
  return generate_endpoints(schema, endpoints, prefix)
end


return Endpoints
