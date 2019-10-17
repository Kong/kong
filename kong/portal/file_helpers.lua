local pl_stringx = require "pl.stringx"
local lyaml      = require "lyaml"
local singletons = require "kong.singletons"
local constants  = require "kong.constants"
local cjson      = require "cjson.safe"

local decode_base64 = ngx.decode_base64
local split = pl_stringx.split
local yaml_load = lyaml.load
local match = string.match
local gsub  = string.gsub

local EXTENSION_LIST = constants.PORTAL_RENDERER.EXTENSION_LIST
local SPEC_EXT_LIST = constants.PORTAL_RENDERER.SPEC_EXT_LIST
local ROUTE_TYPES    = constants.PORTAL_RENDERER.ROUTE_TYPES
local PRIORITY_INDEX_OFFSET = constants.PORTAL_RENDERER.PRIORITY_INDEX_OFFSET

local content_extension_err = "invalid content extension, must be one of:" .. table.concat(EXTENSION_LIST, ", ")
local spec_extension_err = "invalid spec extension, must be one of:" .. table.concat(SPEC_EXT_LIST, ", ")


local function extension_priority(ext)
  for i, v in ipairs(EXTENSION_LIST) do
    if ext == v then
      return i
    end
  end

  return nil, "extension: not valid"
end


local function to_bool(res)
  return not not res
end

local function get_ext(path)
  return match(path, "%.(%w+)$")
end


local function is_html_ext(path)
  return get_ext(path) == "html"
end


local function is_valid_content_ext(path)
  local ext = get_ext(path)
  for _, v in ipairs(EXTENSION_LIST) do
    if ext == v then
      return true
    end
  end

  return false, content_extension_err
end


local function is_valid_spec_ext(path)
  local ext = get_ext(path)
  for _, v in ipairs(SPEC_EXT_LIST) do
    if ext == v then
      return true
    end
  end

  return false, spec_extension_err

end


local function get_prefix(path)
  return match(path, "^(%w+)/")
end


local function is_content_path(path)
  return get_prefix(path) == "content"
end


local function is_spec_path(path)
  return get_prefix(path) == "specs"
end


local function is_config_path(path)
  return to_bool(match(path, "portal.conf.yaml")) or
         to_bool(match(path, "theme.conf.yaml")) or
         to_bool(match(path, "router.conf.yaml"))
end


local function is_layout_path(path)
  return to_bool(match(path, "^themes/[%w-]+/layouts/"))
end


local function is_partial_path(path)
  return to_bool(match(path, "^themes/[%w-]+/partials/"))
end


local function is_asset_path(path)
  return to_bool(match(path, "^themes/[%w-]+/assets/"))
end


local function is_collection_path(path)
  return is_content_path(path) and to_bool(match(path, "/_[%w-]+/"))
end


local function is_content(file)
  return is_content_path(file.path) and is_valid_content_ext(file.path)
end


local function is_spec(file)
  return is_spec_path(file.path) and is_valid_spec_ext(file.path)
end


local function is_layout(file)
  return is_layout_path(file.path) and is_html_ext(file.path)
end


local function is_partial(file)
  return is_partial_path(file.path) and is_html_ext(file.path)
end


local function is_asset(file)
  return is_asset_path(file.path)
end


local function decode_file(file)
  local contents = file.contents
  local split_content = split(file.contents, ";")

  if next(split_content) and split(split_content[1], ":")[1] == "data" then
    contents = split(split_content[2], ",")[2]
  end

  contents = gsub(contents, "\n", "")

  local decoded_contents = decode_base64(contents)
  if decoded_contents then
    file.contents = decoded_contents
  end

  return file
end


local function get_conf(type)
  local file = singletons.db.files:select_by_path(type .. ".conf.yaml")
  local contents = file and file.contents or ""
  local parsed_content = yaml_load(contents)
  if parsed_content then
    return parsed_content
  end
end


local function get_path_meta(path)
  if pl_stringx.lfind(path, "specs/") == 1 then
    path = string.gsub(path, "specs/", "content/_specs/")
  end

  if not is_content_path(path) then
    return nil, "can only set path with prefix of 'content'"
  end

  if not is_valid_content_ext(path) then
    return nil, "can only set path with file extension: 'txt', 'md', 'html', 'json', 'yaml', or 'yml'"
  end

  local split_path     = pl_stringx.split(path, "/")
  local full_filename  = table.remove(split_path)
  local base_path      = table.concat(split_path, "/")
  local split_filename = pl_stringx.split(full_filename, '.')
  local extension      = table.remove(split_filename)
  local filename       = split_filename[1]

  -- set path priority. The lower the score, the higher the priorty
  local priority = extension_priority(extension)

  -- set nested index routes to lower priority
  if filename == 'index' and priority then
    priority = priority + PRIORITY_INDEX_OFFSET
  end

  return {
    filename = filename,
    extension = extension,
    base_path = base_path,
    full_path = path,
    priority  = priority,
  }
end


local function parse_file_contents(contents)
  local content
  local split_contents = pl_stringx.split(contents, "---")
  local ok, headmatter = pcall(yaml_load, split_contents[2])
  if not ok then
    headmatter = {}
    content = contents
  else
    content = split_contents[3]
  end

  return headmatter, content
end


local function parse_spec_contents(contents)
  local headmatter = {}
  local parsed_contents, ok

  -- first try to parse as JSON
  parsed_contents = cjson.decode(contents)
  if not parsed_contents then
    -- if fail, try as YAML
    ok, parsed_contents = pcall(yaml_load, contents)
    if not ok or not parsed_contents  then
      return headmatter, contents
    end
  end

  if parsed_contents["x-headmatter"] then
    headmatter = parsed_contents["x-headmatter"]
  end

  if parsed_contents["X-headmatter"] then
    headmatter = parsed_contents["X-headmatter"]
  end

  if not headmatter.title and parsed_contents.info and parsed_contents.info.title then
    headmatter.title = parsed_contents.info.title
  end

  return headmatter, contents, parsed_contents
end


local function resolve_route(filename, base_path)
  local route
  if filename == 'index' then
    route = base_path
  end

  if not route then
    route = base_path .. '/' .. filename
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


local function get_collection_conf(route)
  local split_route = pl_stringx.split(route, "/")
  local collection_stub  = split_route[2]
  local collection_name = string.gsub(collection_stub, "_", "", 1)
  local portal_conf = get_conf("portal")
  local valid_collections = portal_conf and portal_conf.collections or {}
  if not valid_collections.specs then
    valid_collections.specs  = {
      output = true,
      layout = "system/spec-renderer.html",
      route = "/documentation/:name",
    }
  end

  local collection_conf = valid_collections[collection_name]
  if collection_conf then
    collection_conf.name = collection_name
    return collection_conf
  end
end


local function parse_content(file)
  local output = true
  local route_type = ROUTE_TYPES.DEFAULT
  local path_meta, err = get_path_meta(file.path)
  if not path_meta then
    return err
  end

  local headmatter, body, parsed
  if is_spec_path(file.path) then
    headmatter, body, parsed = parse_spec_contents(file.contents)
  else
    headmatter, body = parse_file_contents(file.contents)
  end

  if not headmatter or not body then
    return nil, "contents: cannot parse, files with 'content/' prefix must have valid headmatter/body syntax"
  end

  local route = resolve_route(path_meta.filename, path_meta.base_path)
  if not route then
    return nil, "path: cannot parse route"
  end

  local layout
  if headmatter.layout then
    layout = headmatter.layout
  end

  if headmatter.route then
    route_type = ROUTE_TYPES.EXPLICIT
    route = headmatter.route
  end

  if headmatter.output == false then
    output = false
  end

  local is_collection = pl_stringx.rfind(route, "/_") == 1
  if is_collection then
    local collection_conf = get_collection_conf(route)
    if not collection_conf or not collection_conf.output then
      output = false
    end

    -- headmatter route takes precidence
    if not headmatter.route and collection_conf and collection_conf.route then
      route_type = ROUTE_TYPES.COLLECTION
      route = collection_conf.route

      local key_map = {
        [":collection"] = collection_conf.name,
        [":stub"]       = headmatter.stub,
        [":title"]      = headmatter.title,
        [":name"]       = path_meta.filename,
      }

      for k, v in pairs(key_map) do
        route = string.gsub(route, k, v)
      end
    end

    -- headmatter layout takes precidence
    if collection_conf.layout and not headmatter.layout then
      layout = collection_conf.layout
    end
  end

  -- set route to nil if content should not be output
  if not output then
    route = nil
  end

  return {
    path       = file.path,
    created_at = file.created_at,
    updated_at = file.updated_at,
    headmatter = headmatter,
    route_type = route_type,
    path_meta  = path_meta,
    layout     = layout,
    route      = route,
    body       = body,
    parsed     = parsed, -- specs only
  }
end


return {
  is_content      = is_content,
  is_spec         = is_spec,
  is_content_path = is_content_path,
  is_collection_path = is_collection_path,
  is_config_path  = is_config_path,
  is_spec_path    = is_spec_path,
  is_valid_content_ext = is_valid_content_ext,
  is_valid_spec_ext = is_valid_spec_ext,
  is_layout       = is_layout,
  is_layout_path  = is_layout_path,
  is_partial      = is_partial,
  is_partial_path = is_partial_path,
  is_asset        = is_asset,
  is_asset_path   = is_asset_path,
  is_html_ext     = is_html_ext,
  get_prefix      = get_prefix,
  get_ext         = get_ext,
  decode_file     = decode_file,
  get_path_meta   = get_path_meta,
  parse_content   = parse_content,
  get_conf        = get_conf,
}
