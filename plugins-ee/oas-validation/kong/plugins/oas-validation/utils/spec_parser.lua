-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local split         = require("pl.utils").split
local clone         = require "table.clone"
local utils         = require("kong.tools.utils")
local lrucache      = require "resty.lrucache"
local cjson         = require("cjson.safe").new()
local lyaml         = require "lyaml"
local normalize     = require("kong.tools.uri").normalize


local ngx           = ngx
local gsub          = string.gsub
local match         = string.match
local json_decode   = cjson.decode
local yaml_load     = lyaml.load
local sha256_hex    = utils.sha256_hex


local SCHEMA_CACHE_SIZE = 1000
local schema_cache = lrucache.new(SCHEMA_CACHE_SIZE)


local function get_path_from_tree(path, tree)
  assert(type(path) == "string", "path must be a string")
  assert(type(tree) == "table", "tree must be a table")

  local segments = split(path, "%/")
  if path == "/" then
    -- top level reference, to full document
    return tree

  elseif segments[1] == "" then
    -- starts with a '/', so remove first empty segment
    table.remove(segments, 1)

  else
    -- first segment is not empty, so we had a relative path
    return nil, "only absolute references are supported, not " .. path
  end

  local position = tree
  for i = 1, #segments do
    position = position[segments[i]]
    if position == nil then
      return nil, "not found"
    end

    if i < #segments and type(position) ~= "table" then
      return nil, "next level cannot be dereferenced, expected table, got " .. type(position)
    end
  end

  return position
end


local function get_dereferenced_schema(full_spec)
  -- deref schema in-place
  local function dereference_single_level(schema, parent_ref)
    for key, value in pairs(schema) do
      local curr_parent_ref = clone(parent_ref)
      if type(value) == "table" and value["$ref"] then
        local reference = value["$ref"]
        if curr_parent_ref[reference] then
          return nil, "recursion detected in schema dereferencing"
        end
        curr_parent_ref[reference] = true

        local file, path = reference:match("^(.-)#(.-)$")
        if not file then
            return nil, "bad reference: " .. reference
        elseif file ~= "" then
            return nil, "only local references are supported, not " .. reference
        end

        local ref_target, err = get_path_from_tree(path, full_spec)
        if not ref_target then
            return nil, "failed dereferencing schema: " .. err
        end
        value = utils.cycle_aware_deep_copy(ref_target)
        schema[key] = value
      end

      if type(value) == "table" then
        local ok, err = dereference_single_level(value, curr_parent_ref)
        if not ok then
            return nil, err
        end
      end
    end

    return schema
  end

  -- wrap to also deref top level
  local schema = utils.cycle_aware_deep_copy(full_spec)
  local wrapped_schema, err = dereference_single_level( { schema }, {} )
  if not wrapped_schema then
      return nil, err
  end

  return wrapped_schema[1]
end


-- Loads an api specification string
-- Tries to first read it as json, and if failed as yaml
local function load_spec(spec_str)
  local spec_sha256_cache_key = tostring(sha256_hex(spec_str))
  local cached_spec = schema_cache:get(spec_sha256_cache_key)
  if cached_spec ~= nil then
    return cached_spec
  end

  -- yaml specs need to be url encoded, otherwise parsing fails
  spec_str = ngx.unescape_uri(spec_str)

  -- first try to parse as JSON
  local result, cjson_err = json_decode(spec_str)
  if type(result) ~= "table" then
    -- if fail, try as YAML
    local ok
    ok, result = pcall(yaml_load, spec_str)
    if not ok or type(result) ~= "table" then
      return nil, ("api specification is neither valid json ('%s') nor valid yaml ('%s')"):
                  format(tostring(cjson_err), tostring(result))
    end
  end

  -- build de-referenced specification
  local deref_schema, err = get_dereferenced_schema(result)
  if err then
    return nil, err
  end

  -- sort paths for later path matching
  local sorted_paths = {}
  if not deref_schema.paths then
    return nil, "no paths defined in specification"
  end

  for n in pairs(deref_schema.paths) do
     table.insert(sorted_paths, n)
  end

  table.sort(sorted_paths)
  deref_schema.sorted_paths = sorted_paths

  schema_cache:set(spec_sha256_cache_key, deref_schema)
  return deref_schema
end


local PATH_METHODS = {}
for m in string.gmatch("GET POST PUT PATCH DELETE OPTIONS HEAD TRACE", "[^%s]+") do
  PATH_METHODS[m] = string.lower(m)
end

local function retrieve_method_path(path, method)
  local path_method = PATH_METHODS[method]
  if path_method then
    return path[path_method]
  end
  return nil
end


local function get_method_spec(conf, uri_path, method)
  local paths = conf.parsed_spec.paths
  local method_spec

  for _, path in ipairs(conf.parsed_spec.sorted_paths) do
    local formatted_path = gsub(path, "[-.]", "%%%1")
    -- replace path parameters with patterns
    formatted_path = "^" .. gsub(formatted_path, "{(.-)}", "[A-Za-z0-9._-]+") .. "$"

    local matched_path = match(uri_path, formatted_path)
    if matched_path then
      method_spec = retrieve_method_path(paths[path], method)

      if method_spec then
        return method_spec, path, paths[path].parameters
      end
    end
  end

  return nil, nil, nil, "path not found in api specification"
end


local function get_spec_from_conf(conf, path, method)
  local path = normalize(path, true)
  -- store parsed spec
  local err
  if conf.api_spec and not conf.parsed_spec then
    conf.parsed_spec, err = load_spec(conf.api_spec)

    if not conf.parsed_spec then
      return nil, nil, nil, string.format("Unable to parse the api specification: %s", err)
    end
  end

  return get_method_spec(conf, path, method)
end


return {
  get_dereferenced_schema = get_dereferenced_schema,
  load_spec = load_spec,
  get_method_spec = get_method_spec,
  get_spec_from_conf = get_spec_from_conf,
}
