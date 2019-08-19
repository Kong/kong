local lyaml      = require "lyaml"
local cjson      = require "cjson.safe"
local pl_stringx = require "pl.stringx"
local file_helpers = require "kong.portal.file_helpers"

local yaml_load   = lyaml.load
local EXTENSION_LIST = file_helpers.content_extension_list


local function extension_priority(ext)
  for i, v in ipairs(EXTENSION_LIST) do
    if ext == v then
      return i
    end
  end
end


local function get_file_attrs_by_path(path)
  local split_path     = pl_stringx.split(path, "/")
  local full_filename  = table.remove(split_path)
  local base_path      = table.concat(split_path, "/")
  local split_filename = pl_stringx.split(full_filename, '.')
  local extension      = table.remove(split_filename)
  local filename       = split_filename[1]

  -- set path priority. The lower the score, the higher the priorty
  local priority = extension_priority(extension)

  -- set nested index routes priority lower
  if filename == 'index' and priority then
    priority = priority + 6
  end

  return {
    filename = filename,
    extension = extension,
    base_path = base_path,
    full_path = path,
    priority  = priority
  }
end


local function get_route_from_path(path)
  if not file_helpers.is_content_path(path) then
    return nil, "can only set path with prefix of 'content'"
  end

  if not file_helpers.is_valid_content_ext(path) then
    return nil, "can only set path with file extension: 'txt', 'md', 'html', 'json', 'yaml', or 'yml'"
  end

  local route
  local path_attrs = get_file_attrs_by_path(path)

  if path_attrs.filename == 'index' then
    route = path_attrs.base_path
  end

  if not route then
    route = path_attrs.base_path .. '/' .. path_attrs.filename
  end

  if (pl_stringx.split(route, "content/")[2]) then
    route = pl_stringx.split(route, "content/")[2]
  end

  if route == "content" then
    route = "/"
  end

  if string.sub(route, 1, 1) ~= "/" then
    route = "/" .. route
  end

  return route
end


local function parse_oas(oas_contents)
  if type(oas_contents) ~= "string" or oas_contents == "" then
    return nil, "spec is required"
  end

  local table, ok

  -- first try to parse as JSON
  table = cjson.decode(oas_contents)
  if not table then
    -- if fail, try as YAML
    ok, table = pcall(yaml_load, oas_contents)
    if not ok then
      return nil, "Failed to convert spec to table " .. table
    end
  end

  return table
end


return {
  get_file_attrs_by_path = get_file_attrs_by_path,
  get_route_from_path    = get_route_from_path,
  parse_oas              = parse_oas,
}

