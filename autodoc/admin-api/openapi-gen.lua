setmetatable(_G, nil) -- silence OpenResty's global var warnings

local admin_api_data = require "autodoc.admin-api.data.admin-api"
local kong_meta = require "kong.meta"
local lfs = require "lfs"
local lyaml = require "lyaml"
local typedefs = require "kong.db.schema.typedefs"

local OPENAPI_VERSION = "3.1.0"
local KONG_CONTACT_NAME = "Kong"
local KONG_CONTACT_URL = "https://github.com/Kong/kong"
local LICENSE_NAME = "Apache 2.0"
local LICENSE_URL = "https://github.com/Kong/kong/blob/master/LICENSE"

local METHOD_NA_DBLESS = "This method is not available when using DB-less mode."
local METHOD_ONLY_DBLESS = "This method is only available when using DB-less mode."

local HTTP_METHODS = {
  ["GET"] = true,
  ["HEAD"] = true,
  ["POST"] = true,
  ["PUT"] = true,
  ["DELETE"] = true,
  ["CONNECT"] = true,
  ["OPTIONS"] = true,
  ["TRACE"] = true,
  ["PATCH"] = true,
}

local entities_path = "kong/db/schema/entities"
local routes_path = "kong/api/routes"

-- workaround to load module files
_KONG = require("kong.meta")          -- luacheck: ignore
kong = require("kong.global").new()   -- luacheck: ignore
kong.configuration = {                -- luacheck: ignore
  loaded_plugins = {},
  loaded_vaults = {},
}
kong.db = require("kong.db").new({    -- luacheck: ignore
  database = "postgres",
})
kong.configuration = { -- luacheck: ignore
  loaded_plugins = {},
  loaded_vaults = {},
}



local property_format = {
  ["auto_timestamp_ms"] = "float",
  ["auto_timestamp_s"] = "int32",
  ["host"] = "hostname",
  ["ip"] = "ip",
  ["port"] = "int32",
  ["uuid"] = "uuid",
}

local property_type = {
  ["array"] = "array",
  ["boolean"] = "boolean",
  ["foreign"] = nil,
  ["integer"] = "integer",
  ["map"] = "array",
  ["number"] = "number",
  ["record"] = "array",
  ["set"] = "array",
  ["string"] = "string",
  ["auto_timestamp_ms"] = "number",
  ["auto_timestamp_s"] = "integer",
  ["destinations"] = "array",
  ["header_name"] = "string",
  ["host"] = "string",
  ["host_with_optional_port"] = "string",
  ["hosts"] = "array",
  ["ip"] = "string",
  ["methods"] = "array",
  ["path"] = "string",
  ["paths"] = "array",
  ["port"] = "integer",
  ["protocols"] = "array",
  ["semantic_version"] = "string",
  ["sources"] = "array",
  ["tag"] = "string",
  ["tags"] = "array",
  ["utf8_name"] = "string",
  ["uuid"] = "string",
}

local property_enum = {
  ["protocols"] = {
    "http",
    "https",
    "tcp",
    "tls",
    "udp",
    "grpc",
    "grpcs"
  },
}

local property_minimum = {
  ["port"] = 0,
}

local property_maximum = {
  ["port"] = 65535,
}


local function sanitize_text(text)
  if text == nil then
    return text
  end

  if type(text) ~= "string" then
    error("invalid type received: " .. type(text) ..
          ". sanitize_text() sanitizes text", 2)
  end

  -- remove all <div></div> from text
  text = text:gsub("<div.->(.-)</div>","")

  return text
end


local function get_openapi()
  local openapi = OPENAPI_VERSION

  return openapi
end


local function get_info()
  local info = {
    ["title"] = "Kong Admin API",
    ["summary"] = "Kong RESTful Admin API for administration purposes.",
    ["description"] = sanitize_text(admin_api_data["intro"][1]["text"]),
    ["version"] = kong_meta._VERSION,
    ["contact"] = {
      ["name"] = KONG_CONTACT_NAME,
      ["url"] = KONG_CONTACT_URL,
      --["email"] = "",
    },
    ["license"] = {
      ["name"] = LICENSE_NAME,
      ["url"] = LICENSE_URL,
    },
  }

  return info
end


local function get_servers()
  local servers = {
    {
      ["url"] = "http://localhost:8001",
      ["description"] = "8001 is the default port on which the Admin API listens.",
    },
    {
      ["url"] = "https://localhost:8444",
      ["description"] = "8444 is the default port for HTTPS traffic to the Admin API.",
    },
  }

  return servers
end


local function get_package_from_path(path)
  if type(path) ~= "string" then
    error("path must be a string, but it is " .. type(path), 2)
  end

  local package = path:gsub("(.lua)","")
  package = package:gsub("/",".")

  return package
end


local function get_property_reference(reference)
  local reference_path

  if reference ~= nil and type(reference) == "string" then
    reference_path = "#/components/schemas/" .. reference
  end

  return reference_path
end


local function get_full_type(properties)
  local actual_type

  if properties.type == nil or properties.type == "foreign" then
    return nil
  end

  for type_name, type_content in pairs(typedefs) do
    if properties == type_content then
      actual_type = type_name
      break
    end
  end

  if actual_type == nil and properties.type then
    actual_type = properties.type
  end

  return actual_type
end


local function get_field_details(field_properties)
  local details = {}

  local actual_type = get_full_type(field_properties)
  if actual_type then
    details.type = property_type[actual_type]
    details.format = property_format[actual_type]
    details.enum = property_enum[actual_type]
    details.minimum = property_minimum[actual_type]
    details.maximum = property_maximum[actual_type]
  end

  details["$ref"] = get_property_reference(field_properties.reference)
  if field_properties.default == ngx.null then
    details.nullable = true
    details.default = lyaml.null
  else
    details.default = field_properties.default
  end

  return details
end


local function get_properties_from_entity_fields(fields)
  local properties = {}
  local required = {}

  for _, field in ipairs(fields) do
    for field_name, field_props in pairs(field) do
      properties[field_name] = get_field_details(field_props)
      if field_props.required then
        table.insert(required, field_name)
      end
    end
  end

  return properties, required
end


local function get_schemas()
  local schemas = {}

  for file in lfs.dir(entities_path) do
    if file ~= "." and file ~= ".." then
      local entity_path = entities_path .. "/" .. file
      local entity_package = get_package_from_path(entity_path)
      local entity = require(entity_package)
      if entity then
        if entity.name then -- TODO: treat special case "routes_subschemas"
          local entity_content = {}
          entity_content.type = "object"
          entity_content.properties, entity_content.required = get_properties_from_entity_fields(entity.fields)
          schemas[entity.name] = entity_content
        end
      end
    end
  end

  return schemas
end


local function get_components()
  local components = {}
  components.schemas = get_schemas()

  return components
end


local function get_all_routes()
  local routes = {}

  for file in lfs.dir(routes_path) do
    if file ~= "." and file ~= ".." then
      local route_path = routes_path .. "/" .. file
      local route_package = get_package_from_path(route_path)
      local route = require(route_package)
      table.insert(routes, route)
    end
  end

  return routes
end


local function is_http_method(name)
  return HTTP_METHODS[name] == true
end


local function translate_path(entry)
  if entry:len() < 2 then
    return entry
  end

  local translated = ""

  for segment in string.gmatch(entry, "([^/]+)") do
    if segment:byte(1) == string.byte(":") then
      segment = "{" .. segment:sub(2, segment:len()) .. "}"
    end
    translated = translated .. "/" .. segment
  end

  return translated
end


local function fill_paths(paths)
  local entities = admin_api_data.entities
  local general_routes = admin_api_data.general
  local path_content = {}

  -- extract path details from entities
  for name, entity in pairs(entities) do
    for entry, content in pairs(entity) do
      if type(entry) == "string" and entry:sub(1,1) == "/" then
        path_content[entry] = content
      end
    end
  end

  -- extract path details from general entries
  for x, content in pairs(general_routes) do
    if type(content) == "table" then
      for entry, entry_content in pairs(content) do
        if type(entry) == "string" and entry:sub(1,1) == "/" then
          path_content[entry] = entry_content
        end
      end
    end
  end

  -- fill received paths
  for path, methods in pairs(paths) do
    for method, content in pairs(methods) do
      if path == "/config" then
        content.description = METHOD_ONLY_DBLESS
      elseif method ~= "get" then
        content.description = METHOD_NA_DBLESS
      end

      if path_content[path] and path_content[path][method:upper()] then
        content.summary = path_content[path][method:upper()].title
      end
    end

    -- translate :entity to {entity} in paths
    local actual_path = translate_path(path)
    if actual_path ~= path then
      paths[actual_path] = paths[path]
      paths[path] = nil
    end
  end

end


local function get_paths()
  local paths = {}
  local routes = get_all_routes()

  for _, route in ipairs(routes) do
    for entry, functions in pairs(route) do
      if type(entry) == "string" and entry:sub(1,1) == "/" then
        paths[entry] = {}
        for function_name, _ in pairs(functions) do
          if is_http_method(function_name) then
            paths[entry][function_name:lower()] = {}
          end
        end
      end
    end
  end

  fill_paths(paths)

  return paths
end


local function write_file(filename, content)
  local pok, yaml, err = pcall(lyaml.dump, { content })
  if not pok then
    error("lyaml failed: " .. yaml, 2)
  end
  if not yaml then
    print("creating yaml failed: " .. err, 2)
  end

  -- drop the multi-document "---\n" header and "\n..." trailer
  local content = yaml:sub(5, -5)
  if content then
    local file, errmsg = io.open(filename, "w")
    if errmsg then
      error("could not open " .. filename .. " for writing: " .. errmsg, 2)
    end
    file:write(content)
    file:close()
  end

end


local function main(filepath)

  local openapi_spec_content = {}

  openapi_spec_content.openapi = get_openapi()
  openapi_spec_content.info = get_info()
  openapi_spec_content.servers = get_servers()
  openapi_spec_content.components = get_components()
  openapi_spec_content.paths = get_paths()

  write_file(filepath, openapi_spec_content)
end


main(arg[1])
