local parse_openapi = require "kong.enterprise_edition.openapi2kong.openapi"
local lyaml = require "lyaml"
local cjson = require "cjson.safe"
local utils = require "pl.utils"
local gsub = string.gsub
local tablex = require "pl.tablex"
local table_deepcopy = tablex.deepcopy
local path = require "pl.path"

local pack = function(...)  -- nil safe version of pack
  return { n = select("#", ...), ...}
end


local SERVERS_TYPES = {  -- types having a `servers` array
  openapi = true,
  path = true,
  operation = true,
}


--- Loads a spec string.
-- Tries to first read it as json, and if failed as yaml.
-- @param spec_str (string) the string to load
-- @return table or nil+err
local function load_spec(spec_str)

  -- first try to parse as JSON
  local result, cjson_err = cjson.decode(spec_str)
  if type(result) ~= "table" then
    -- if fail, try as YAML
    local ok
    ok, result = pcall(lyaml.load, spec_str)
    if not ok or type(result) ~= "table" then
      return nil, ("Spec is neither valid json ('%s') nor valid yaml ('%s')"):
                  format(tostring(cjson_err), tostring(result))
    end
  end

  return result
end



-- removes all non-allowed characters from a tag name
local function clean_tag(tag)
  return tag:gsub("[^%w%_%-%.%~]", "_")
end


-- return a NEW table, with all tags combined, without duplication.
-- Each parameter should be a list of tags
local function get_tags(...)
  local params = pack(...)
  local tags = {}
  local check = {}

  for i = 1, params.n do
    for _,v in ipairs(params[i] or {}) do
      v = clean_tag(v)
      if not check[v] then
        tags[#tags+1] = v
        check[v] = true
      end
    end
  end

  return tags
end


local registry_add, registry_get
do
  local registry = setmetatable({}, { __mode = "kv" })

  --- Add an entry to the generation registry.
  -- The registry keeps track of what Kong entities were generated from OpenAPI
  -- objects. The key is an OpenAPI object (eg. "path", or "servers"), and the
  -- values attached to it the will be the Kong entities.
  function registry_add(key, value1, value2)
    assert(type(key) == "table", "expected key to be an OpenApi parsed object")
    assert(not registry[key], "this key was already registered")
    local type_obj = key.type
    assert(type_obj, "expected key to be an OpenApi parsed object")

    if type_obj == "servers" then
      registry[key] = {
        upstream = assert(value1.targets and value1, "expected first value to be an Upstream"),
        service = assert(value2.path and value2, "expected second value to be a Service"),
      }

    elseif type_obj == "operation" then
      registry[key] = assert(value1.strip_path ~= nil and value1 , "expected first value to be a Route")
      assert(value2 == nil, "did not expect a second value for 'operation'")

    elseif type_obj == "securityRequirements" then

--local p
--p, value1.parent = value1.parent, nil
--require"pl.pretty"(value1)
--value1.parent = p
      registry[key] = assert(value1.name ~= nil and value1.config ~= nil and value1 , "expected first value to be a Plugin")
      assert(value2 == nil, "did not expect a second value for 'securityRequirements'")

    else
      error("cannot add object (key) of type: " .. type_obj, 2)
    end
  end

  --- Gets an entry from the generation registry.
  function registry_get(key)
    assert(type(key) == "table", "expected key to be an OpenApi parsed object")
    assert(key.type, "expected key to be an OpenApi parsed object")
    return registry[key]
  end
end


-- finds the next "x-kong-xxxx" custom extension.
-- returns a copy of the default table, or an empty table if not found
local function get_kong_defaults(obj, custom_directive, types)
  local default, err, owning_obj = obj:get_inherited_property(custom_directive, types)
  if err and err ~= "not found" then
    return nil, err
  end
  if default then
    default = owning_obj:dereference_x_kong(custom_directive)
    default = table_deepcopy(default)
  end

  return default or {}
end

-- finds the next "x-kong-upstream-defaults" custom extension
local function get_upstream_defaults(obj)
  return get_kong_defaults(obj, "x-kong-upstream-defaults", SERVERS_TYPES)
end

-- finds the next "x-kong-service-defaults" custom extension
local function get_service_defaults(obj)
  return get_kong_defaults(obj, "x-kong-service-defaults", SERVERS_TYPES)
end

-- finds the next "x-kong-route-defaults" custom extension
local function get_route_defaults(obj)
  return get_kong_defaults(obj, "x-kong-route-defaults", SERVERS_TYPES)
end

-- finds the next "x-kong-security-xxx" custom extension, no inheritance!
-- extensions are `x-kong-security-xxx` where `xxx` is the plugin name used
local function get_securityScheme_defaults(obj)
  local t = obj.spec.type
  local types = { [obj.type] = true,
                  openapi    = true } -- allow our own type, and top level
  if t == "oauth2" then
    return get_kong_defaults(obj, "x-kong-security-openid-connect", types)

  elseif t == "openIdConnect" then
    return get_kong_defaults(obj, "x-kong-security-openid-connect", types)

  elseif t == "apiKey" then
    return get_kong_defaults(obj, "x-kong-security-key-auth", types)

  elseif t == "http" and obj.spec.scheme:lower() == "basic" then
    return get_kong_defaults(obj, "x-kong-security-basic-auth", types)

  else
    error("unsupported security type: "..tostring(t))
  end
end

--- returns all "servers" objects from the openapi spec.
local function  get_all_servers(openapi)
  local servers_arr = { openapi.servers }

  for _, path_obj in ipairs(openapi.paths) do
    servers_arr[#servers_arr+1] = path_obj.servers
  end

  return servers_arr
end

--- Converts "servers" object to "upstreams", "targets", and "services".
-- @param openapi (table) openapi object as parsed from the spec.
-- @param options table with conversion options
-- @return kong table (options.kong, updated) or nil+err.
local function convert_servers(openapi, options)
  local servers_arr = get_all_servers(openapi)
  local kong = options.kong
  local upstreams = kong.upstreams
  local services = kong.services

  for _, servers in ipairs(servers_arr) do
    -- upstream
    local targets = {}

    -- add targets
    for _, server in ipairs(servers) do
      targets[#targets+1] = {
        target = server.parsed_url.host .. ":" .. server.parsed_url.port,
      }
    end

    local upstream = get_upstream_defaults(servers)
    upstream.name = servers:get_name(options)
    upstream.targets = targets
    upstream.tags = get_tags(options.tags, upstream.tags)

    upstreams[#upstreams+1] = upstream

    -- service
    local url = servers[1].parsed_url

    local service = get_service_defaults(servers)
    service.name = servers:get_name(options)
    service.protocol = url.scheme
    service.port = tonumber(url.port)
    service.host = servers:get_name(options)
    service.path = "/"
    service.tags = get_tags(options.tags, service.tags)

    services[#services+1] = service

    -- register entities
    registry_add(servers, upstream, service)
  end

  return kong
end


local create_security_plugin
do
  local creators = {

    http = function(securityScheme)
      if securityScheme.spec.scheme:lower() ~= "basic" then
        return nil, "securityScheme http only supports `basic`, not: " .. securityScheme.spec.scheme
      end

      local plugin = get_securityScheme_defaults(securityScheme)
      plugin.name = "basic-auth"
      plugin.config = plugin.config or {}

      return plugin
    end, -- http

    apiKey = function(securityScheme)
      if securityScheme.spec["in"] == "cookie" then
        return nil, "apiKey in 'cookie' is not supported"
      end

      local plugin = get_securityScheme_defaults(securityScheme)
      plugin.name = "key-auth"
      plugin.config = plugin.config or {}

      plugin.config.key_names = plugin.config.key_names or {}
      local duplicate = false
      for _, key_name in ipairs(plugin.config.key_names) do
        if key_name == securityScheme.spec.name then
          duplicate = true
        end
      end
      if not duplicate then
        plugin.config.key_names[#plugin.config.key_names+1] = securityScheme.spec.name
      end
      return plugin
    end, -- apiKey

    openIdConnect = function(securityScheme)
      local plugin = get_securityScheme_defaults(securityScheme)
      plugin.name = "openid-connect"
      plugin.config = plugin.config or {}

      local scopes_required = plugin.config.scopes_required or {}
      for _, scope_to_add in ipairs(securityScheme.scopes) do
        local set_scope = true
        for _, existing_scope in ipairs(scopes_required) do
          if existing_scope == scope_to_add then
            set_scope = false
            break
          end
        end
        if set_scope then
          scopes_required[#scopes_required+1] = scope_to_add
        end
      end

      plugin.config.issuer = securityScheme.spec.openIdConnectUrl
      plugin.config.scopes_required = scopes_required

      return plugin
    end, -- openIdConnect

    oauth2 = function(securityScheme)
      -- oauth2 is also implementated using OIDC plugin
      local plugin = get_securityScheme_defaults(securityScheme)
      plugin.name = "openid-connect"
      plugin.config = plugin.config or {}

      local auth_methods = plugin.config.auth_methods or {}
      local authorizationUrl
      local tokenUrl
      local refreshUrl

      for _, flow_obj in ipairs(securityScheme.flows) do
        local flow = flow_obj.flow_type

        if     flow == "password"          then flow = "password"
        --elseif flow == "implicit"          then flow = "???"
        elseif flow == "clientCredentials" then flow = "client_credentials"
        elseif flow == "authorizationCode" then flow = "authorization_code"
        else return nil, "unsupported flow: " .. flow
        end

        auth_methods[#auth_methods+1] = flow

        if authorizationUrl and flow_obj.authorizationUrl then
          if authorizationUrl ~= flow_obj.authorizationUrl then
            return nil, "authorizationUrl must be identical for multiple flows"
          end
        end
        authorizationUrl = flow_obj.authorizationUrl

        if tokenUrl and flow_obj.tokenUrl then
          if tokenUrl ~= flow_obj.tokenUrl then
            return nil, "tokenUrl must be identical for multiple flows"
          end
        end
        tokenUrl = flow_obj.tokenUrl

        if refreshUrl and flow_obj.refreshUrl then
          if refreshUrl ~= flow_obj.refreshUrl then
            return nil, "refreshUrl must be identical for multiple flows"
          end
        end
        refreshUrl = flow_obj.refreshUrl
      end

      plugin.config.auth_methods = auth_methods
      plugin.config.paramx = authorizationUrl
      plugin.config.paramy = tokenUrl
      plugin.config.paramz = refreshUrl

      return plugin
    end,  -- oauth2
  }

  function create_security_plugin(securityScheme)
    return creators[securityScheme.spec.type](securityScheme)
  end
end

-- takes the "operation" object and generates the plugin configuration to
-- validate the request.
-- @param operation_obj the operations object
-- @return the `config` table for the plugin entity
local function generate_validation_config(operation_obj)
  assert(operation_obj.type == "operation", "expected an operation object")
  local config = {
    version = "draft4",
  }

  -- Parameters
  local parameter_schema = {}
  if operation_obj.parameters then
    for param in operation_obj.parameters:iterate() do
      if param.schema then
        local spec = {
          ["in"] = param["in"],
          name = param.name,
          style = param.style,
          explode = param.explode,
          required = param.required,
          schema = assert(cjson.encode(param.schema:get_dereferenced_schema()))
        }
        parameter_schema[#parameter_schema+1] = spec
      else
        return nil, "Parameter using 'content' type validation is not supported"
      end
    end
  end
  if #parameter_schema > 0 then
    config.parameter_schema = parameter_schema
  end

  -- Body
  local body_schema
  if operation_obj.requestBody then
    for _, media_type in ipairs(operation_obj.requestBody) do
      if media_type.mediatype == "application/json" then
        assert(not body_schema, "body_schema was already set!")
        body_schema = assert(cjson.encode(media_type.schema:get_dereferenced_schema()))
      else
        return nil, ("Body validation supports only 'application/json', " ..
                     "not '%s'"):format(tostring(media_type.mediatype))
      end
    end
  end
  if body_schema then
    config.body_schema = body_schema
  end

  return config
end

--- Converts "paths" object to "routes", and "plugins".
-- @param openapi (table) openapi object as parsed from the spec.
-- @param options table with conversion options
-- @return kong table (options.kong, updated) or nil+err.
local function convert_paths(openapi, options)
  local kong = options.kong

  for _, path_obj in ipairs(openapi.paths) do

    local path = path_obj:get_servers()[1].parsed_url.path or "/"
    if path:sub(-1,-1) == "/" and
       path_obj.path:sub(1,1) == "/" then
      -- double slashes, drop one
      path = path .. path_obj.path:sub(2,-1)
    else
      path = path .. path_obj.path
    end

    -- convert path into a regex
    -- 1) add template parameters
    -- TODO: adjust the regex created here. OAS 3 does not support multiple segment capture
    -- see https://github.com/OAI/OpenAPI-Specification/issues/291#issuecomment-316593913
    -- So the regex should match non-empty, no /, no ?, no #
    path = gsub(path, "{(.-)}", "(?<%1>\\S+)")

    -- 2) anchor the match, because we're matching in full, not just prefixes
    path = path .. "$"

    local service = registry_get(path_obj:get_servers()).service
    service.routes = service.routes or {}

    for _, operation_obj in ipairs(path_obj.operations) do

      local route = get_route_defaults(operation_obj)
      route.name = operation_obj:get_name()
      route.paths = { path }
      route.methods = { operation_obj.method:upper() }
      route.strip_path = false
      route.plugins = route.plugins or {}
      route.tags = get_tags(options.tags, route.tags)
      --TODO: set regex_priority property to match in proper order??

      -- store the final route on the service
      service.routes[#service.routes+1] = route

      -- register entities
      registry_add(operation_obj, route)

      do -- check security plugins required
        local requirements, err = operation_obj:get_security()
        if (not requirements) and err ~= "not found" then
          return nil, operation_obj:log_message(err)
        end

        if requirements and #requirements > 0 then
          if #requirements > 1 then
            return nil, operation_obj:log_message("maximum of 1 Security Requirement supported, got " .. #requirements)
          end

          local security_requirement = requirements[1]
          if #security_requirement > 1 then
            return nil, operation_obj:log_message("maximum of 1 Security Scheme supported, got " .. #security_requirement)
          end

          local plugin_conf = registry_get(requirements)
          if not plugin_conf then
            plugin_conf, err = create_security_plugin(security_requirement[1])
            if not plugin_conf then
              return nil, operation_obj:log_message(err)
            end

            registry_add(requirements, plugin_conf)
          end

          route.plugins[#route.plugins+1] = plugin_conf
        end
      end -- check security plugins required

      local request_validator_config
      do  -- check other plugins to be added
        for plugin_name, plugin_table in pairs(operation_obj:get_plugins()) do
          route.plugins[#route.plugins+1] = plugin_table

          -- if it is a validator without config, then we need to hold on to it
          if plugin_name == "request-validator" then
            request_validator_config = plugin_table
          end
        end
      end -- check other plugins to be added

      do -- request validation
        if request_validator_config and request_validator_config.config == nil then
          local err
          request_validator_config.config, err = generate_validation_config(operation_obj)
          if not request_validator_config.config then
            return nil, operation_obj:log_message(err)
          end

          -- anything to validate?
          if not (request_validator_config.config.body_schema or
                  request_validator_config.config.parameter_schema) then
            -- if there is nothing to validate, so remove it again
            -- typically happens if inherited from top-level OpenAPI on a
            -- path without parameter/body
            for i, plugin in ipairs(route.plugins) do
              if plugin == request_validator_config then
                table.remove(route.plugins, i)
                break
              end
            end
          end

        end
      end -- request validation

      if #route.plugins == 0 then
        route.plugins = nil
      end
    end  -- for: Operations

  end  -- for: Paths

  return kong
end


-- returns a basic Kong spec
local function new_kong()
  return {
    _format_version = "1.1",
  }
end


--- Convert an OpenAPI spec table and convert it to a Kong table.
-- @param openapi (table) openapi object as parsed from the spec.
-- @param options table with conversion options;
--  - `kong` (optional) an existing kong spec to add to
-- @return table or nil+err
local function to_kong(openapi, options)
  options = options or {}
  options.kong = options.kong or new_kong()
  options.kong.upstreams = options.kong.upstreams or {}
  options.kong.services = options.kong.services or {}


  local ok, err = convert_servers(openapi, options)
  if not ok then
    return nil, "Failed to convert servers: " .. tostring(err)
  end

  ok, err = convert_paths(openapi, options)
  if not ok then
    return nil, "Failed to convert paths: " .. tostring(err)
  end

  return options.kong
end


--- Takes an OpenAPI spec and returns it as a Kong config.
-- @param spec_input the OpenAPI spec to convert. Can be a either a table, a json-string, or a yaml-string.
-- @param options table with conversion options
-- @return table with kong spec, or nil+err
local function convert_spec(spec_input, options)
  if type(spec_input) == "string" then
    local err
    spec_input, err = load_spec(spec_input)
    if not spec_input then
      return nil, err
    end
  end

  local openapi_obj, err = parse_openapi(spec_input, options)
  if not openapi_obj then
    return nil, err
  end

  local kong_obj
  kong_obj, err = to_kong(openapi_obj, options)
  if not kong_obj then
    return nil, err
  end

  return kong_obj
end

-- @param filenames either a filename (string) or list of filenames (table)
-- @param options table with conversion options
-- @return table with kong spec, or nil+err
local function convert_files(filenames, options)
  if type(filenames) == "string" then
    filenames = { filenames }
  end

  options = options or {}
  options.tags = options.tags or {}
  options.tags[#options.tags + 1] = "OAS3_import"

  local kong = options.kong or new_kong()

  local file_tag_id = #options.tags + 1

  for _, filename in ipairs(filenames) do

    local file_content, err = utils.readfile(filename)
    if not file_content then
      return nil, ("Failed reading '%s': %s"):format(tostring(filename), tostring(err))
    end

    options.import_filename = path.basename(filename)
    options.tags[file_tag_id] = "OAS3file_" .. options.import_filename

    options.kong = kong
    kong, err = convert_spec(file_content, options)
    if not kong then
      return nil, ("Failed converting '%s': %s"):format(tostring(filename), tostring(err))
    end
  end

  return kong
end


return {
  convert_files = convert_files,
  convert_spec = convert_spec,
}
