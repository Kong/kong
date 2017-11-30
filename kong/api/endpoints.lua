local escape_uri = ngx.escape_uri
local concat     = table.concat
local find       = string.find
local null       = ngx.null


local get_collection_endpoint = {
  function (schema_name)
    return function(self, db, helpers)
      local data, _, err_t, offset = db[schema_name]:page(
        self.params.size,
        self.params.offset)

      if err_t then
        return helpers.yield_error(err_t)
      end

      local next_page = offset and concat {
        "/" .. schema_name .. "?offset=" .. escape_uri(offset)
      } or null

      return helpers.responses.send_HTTP_OK{
        data   = data,
        offset = offset,
        next   = next_page,
      }
    end
  end,
  function (schema_name, parent_schema_name, entity_name)
    return function(self, db, helpers)
      -- TODO: composite key support
      local fk = { id = self.params[parent_schema_name] }
      local entity = db[schema_name]

      local rows, _, err_t, offset = entity["for_" .. entity_name](
        entity,
        fk,
        self.params.size,
        self.params.offset)

      if err_t then
        return helpers.yield_error(err_t)
      end

      local next_page = offset and concat {
        "/", parent_schema_name, "/", escape_uri(self.params[schema_name]), "/", schema_name,
        "?offset=", escape_uri(offset)
      } or null

      return helpers.responses.send_HTTP_OK{
        data   = rows,
        offset = offset,
        next   = next_page,
      }
    end
  end
}


local post_collection_endpoint = {
  function(schema_name)
    return function(self, db, helpers)
      -- TODO: composite key support
      self.params[schema_name] = nil
      local data, _, err_t = db[schema_name]:insert(self.params)
      if err_t then
        return helpers.yield_error(err_t)
      end

      return helpers.responses.send_HTTP_CREATED(data)
    end
  end,
  function(schema_name, parent_schema_name, entity_name)
    return function(self, db, helpers)
      -- TODO: composite key support
      self.params[schema_name] = nil
      local data, _, err_t = db[schema_name]:insert(self.params)
      if err_t then
        return helpers.yield_error(err_t)
      end

      return helpers.responses.send_HTTP_CREATED(data)
    end
  end,
}


local get_entity_endpoint = {
  function(schema_name)
    return function(self, db, helpers)
      -- TODO: composite key support
      local pk = { id = self.params[schema_name] }
      local entity, _, err_t = db[schema_name]:select(pk)
      if err_t then
        return helpers.yield_error(err_t)
      end

      if entity then
        return helpers.responses.send_HTTP_OK(entity)
      end

      return helpers.responses.send_HTTP_NOT_FOUND()
    end
  end,
  function(schema_name, parent_schema_name, entity_name)
    return function(self, db, helpers)
      -- TODO: composite key support
      local pk = { id = self.params[parent_schema_name] }
      local parent_entity, _, err_t = db[parent_schema_name]:select(pk)
      if err_t then
        return helpers.yield_error(err_t)
      end

      if not parent_entity or parent_entity[entity_name] == null then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local entity, _, err_t = db[schema_name]:select(parent_entity[entity_name])
      if err_t then
        return helpers.yield_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(entity)
    end
  end,
}


local patch_entity_endpoint = {
  function(schema_name)
    return function(self, db, helpers)
      -- TODO: composite key support
      local pk = { id = self.params[schema_name] }
      self.params[schema_name] = nil
      local entity, _, err_t = db[schema_name]:update(pk, self.params)
      if err_t then
        return helpers.yield_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(entity)
    end
  end,
  function(schema_name, parent_schema_name, entity_name)
    return function(self, db, helpers)
      -- TODO: composite key support
      local pk = { id = self.params[parent_schema_name] }
      self.params[parent_schema_name] = nil
      local parent_entity, _, err_t = db[parent_schema_name]:select(pk)
      if err_t then
        return helpers.yield_error(err_t)
      end

      if not parent_entity or parent_entity[entity_name] == null then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      local entity, _, err_t = db[schema_name]:update(parent_entity[entity_name], self.params)
      if err_t then
        return helpers.yield_error(err_t)
      end

      return helpers.responses.send_HTTP_OK(entity)
    end
  end,
}


local delete_entity_endpoint = {
  function(schema_name)
    return function(self, db, helpers)
      -- TODO: composite key support
      local pk = { id = self.params[schema_name] }
      local _, _, err_t = db[schema_name]:delete(pk)
      if err_t then
        return helpers.yield_error(err_t)
      end

      return helpers.responses.send_HTTP_NO_CONTENT()
    end
  end,
  function(schema_name, parent_schema_name, entity_name)
    return function(self, db, helpers)
      -- TODO: composite key support
      local pk = { id = self.params[parent_schema_name] }
      local parent_entity, _, err_t = db[parent_schema_name]:select(pk)
      if err_t then
        return helpers.yield_error(err_t)
      end

      if not parent_entity or parent_entity[entity_name] == null then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      return helpers.responses.send_HTTP_METHOD_NOT_ALLOWED()

--      local _, _, err_t = db[schema_name]:delete(parent_entity[entity_name])
--      if err_t then
--        return helpers.yield_error(err_t)
--      end
--
--      return helpers.responses.send_HTTP_NO_CONTENT()
    end
  end,
}


local collection_endpoints = {
  function(endpoints, collection_path, schema_name)
    endpoints[collection_path] = {
      --OPTIONS =     method_not_allowed,
      --HEAD    =     method_not_allowed,
      GET     =    get_collection_endpoint[1](schema_name),
      POST    =   post_collection_endpoint[1](schema_name),
      --PUT     =     method_not_allowed,
      --PATCH   =     method_not_allowed,
      --DELETE  =     method_not_allowed,
    }
    return endpoints
  end,
  function(endpoints, collection_path, schema_name, parent_schema_name, entity_name)
    endpoints[collection_path] = {
      --OPTIONS =     method_not_allowed,
      --HEAD    =     method_not_allowed,
      GET     =    get_collection_endpoint[2](schema_name, parent_schema_name, entity_name),
      POST    =   post_collection_endpoint[2](schema_name, parent_schema_name, entity_name),
      --PUT     =     method_not_allowed,
      --PATCH   =     method_not_allowed,
      --DELETE  =     method_not_allowed,
    }
    return endpoints
  end,
}


local entity_endpoints = {
  function (endpoints, entity_path, schema_name)
    endpoints[entity_path] = {
      --OPTIONS =     method_not_allowed,
      --HEAD    =     method_not_allowed,
      GET     =    get_entity_endpoint[1](schema_name),
      --POST    =     method_not_allowed,
      --PUT     =     method_not_allowed,
      PATCH   =  patch_entity_endpoint[1](schema_name),
      DELETE  = delete_entity_endpoint[1](schema_name),
    }
    return endpoints
  end,
  function (endpoints, entity_path, schema_name, parent_schema_name, entity_name)
    endpoints[entity_path] = {
      --OPTIONS =     method_not_allowed,
      --HEAD    =     method_not_allowed,
      GET     =    get_entity_endpoint[2](schema_name, parent_schema_name, entity_name),
      --POST    =     method_not_allowed,
      --PUT     =     method_not_allowed,
      PATCH   =  patch_entity_endpoint[2](schema_name, parent_schema_name, entity_name),
      DELETE  = delete_entity_endpoint[2](schema_name, parent_schema_name, entity_name),
    }
    return endpoints
  end,
}

local function generate_endpoints(schema, endpoints, prefix, parent_schema_name, entity_name)
  local path_prefix = concat {
    prefix or "",
    "/"
  }

  local schema_name = schema.name
  local entity_path

  if prefix and entity_name then
    local entity_key = concat {
      "/",
      entity_name,
      "/"
    }

    if find(path_prefix, entity_key, nil, true) then
      return endpoints
    end

    entity_path = concat {
      path_prefix,
      entity_name,
    }

    entity_endpoints[2](endpoints, entity_path, schema_name, parent_schema_name, entity_name)

    for foreign_field_name, foreign_field in schema:each_field() do
      if foreign_field.type == "foreign" then
        generate_endpoints(foreign_field.schema, endpoints, entity_path, schema_name, foreign_field_name)
      end
    end

  elseif parent_schema_name then
    local collection_key = concat {
      "/:",
      parent_schema_name,
      "/",
    }

    if find(path_prefix, collection_key, nil, true) then
      return endpoints
    end

    local collection_path = concat {
      path_prefix,
      parent_schema_name,
      collection_key,
      schema_name,
    }

    collection_endpoints[2](endpoints, collection_path, schema_name, parent_schema_name, entity_name)

    local entity_key = concat {
      "/:",
      schema_name,
      "/"
    }

    if find(path_prefix, entity_key, nil, true) then
      return endpoints
    end

    entity_path = concat {
      collection_path,
      "/:",
      schema_name,
    }

    entity_endpoints[2](endpoints, entity_path, schema_name, parent_schema_name, entity_name)

    for foreign_field_name, foreign_field in schema:each_field() do
      if foreign_field.type == "foreign" then
        generate_endpoints(foreign_field.schema, endpoints, entity_path, schema_name, foreign_field_name)
      end
    end

  else
    local collection_path = concat {
      path_prefix,
      schema_name,
    }

    collection_endpoints[1](endpoints, collection_path, schema_name)

    entity_path = concat {
      collection_path,
      "/:",
      schema_name,
    }

    entity_endpoints[1](endpoints, entity_path, schema_name)

    for foreign_field_name, foreign_field in schema:each_field() do
      if foreign_field.type == "foreign" then
        generate_endpoints(foreign_field.schema, endpoints, entity_path, schema_name, foreign_field_name)
        generate_endpoints(schema, endpoints, nil, foreign_field.schema.name, foreign_field_name)
      end
    end
  end

  return endpoints
end

local Endpoints = {}


function Endpoints.new(schema, endpoints, prefix)
  return generate_endpoints(schema, endpoints, prefix)
end


return Endpoints
