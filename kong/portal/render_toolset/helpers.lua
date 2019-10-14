local lyaml      = require "lyaml"
local cjson      = require "cjson.safe"
local tablex     = require "pl.tablex"
local stringx    = require "pl.stringx"
local inspect    = require "inspect"
local markdown   = require "kong.portal.render_toolset.markdown"
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
  local split_path     = stringx.split(path, "/")
  local full_filename  = table.remove(split_path)
  local base_path      = table.concat(split_path, "/")
  local split_filename = stringx.split(full_filename, '.')
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

  if (stringx.split(route, "content/")[2]) then
    route = stringx.split(route, "content/")[2]
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


local function is_list(table)
  for k, v in pairs(table) do
    if type(k) ~= "number" then
      return false
    end
  end

  return true
end


local function each(items)
  if is_list(items) then
    return ipairs(items)
  end

  return pairs(items)
end


local function map(items, cb, ...)
  if is_list(items) then
    return tablex.imap(cb, items, ...)
  end

  return tablex.map(cb, items, ...)
end


local function table_insert(tbl, k, v)
  tbl[k] = v
end

local function list_insert(tbl, k, v)
  table.insert(tbl, v)
end


local function filter(items, cb, ...)
  local filtered_items = {}
  local iterator = pairs
  local insert = table_insert

  if is_list(items) then
    iterator = ipairs
    insert = list_insert
  end

  for k, v in iterator(items) do
    if cb(k, v, ...) then
      insert(filtered_items, k, v)
    end
  end

  return filtered_items
end


local function is_spec(_, item)
  local parsed_item = file_helpers.parse_content(item)
  if not parsed_item then
    return false
  end

  local path_meta = parsed_item.path_meta
  if not path_meta then
    return false
  end

  local is_content = stringx.split(path_meta.base_path, '/')[1] == "content"
  local is_spec_extension =
    path_meta.extension == "json" or
    path_meta.extension == "yaml" or
    path_meta.extension == "yml"

  if is_content and is_spec_extension then
    return true
  end

  return false
end


local function parse_spec(v)
  return file_helpers.parse_content(v)
end


local function filter_by_path(items, arg)
  return filter(items, function(_, item)
    local split_path = stringx.split(item.path, "/")
    local arg_path = stringx.split(arg, "/")

     for i, v in ipairs(arg_path) do
      if v ~= split_path[i] then
        return false
      end
    end

     return true
  end)
end


return {
  get_file_attrs_by_path = get_file_attrs_by_path,
  get_route_from_path    = get_route_from_path,
  filter_by_path         = filter_by_path,
  parse_oas              = parse_oas,
  parse_spec             = parse_spec,
  is_spec                = is_spec,
  is_list                = is_list,
  tbl                    = tablex,
  str                    = stringx,
  each                   = each,
  map                    = map,
  filter                 = filter,
  print                  = inspect,
  table_insert           = table_insert,
  list_insert            = list_insert,
  json_decode            = cjson.decode,
  json_encode            = cjson.encode,
  markdown               = markdown,
}

