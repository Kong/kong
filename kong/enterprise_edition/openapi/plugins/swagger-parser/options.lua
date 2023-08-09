-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_tablex = require "pl.tablex"
local socket_url = require "socket.url"

local pairs = pairs
local string_byte = string.byte
local string_sub = string.sub
local copy = pl_tablex.copy

local SLASH_BYTE = string_byte("/")
local EMPTY_T = {}

local DEFAULT_PARSER_OPTIONS = {
  resolve_base_path = false,
}


local function resolve_options(opts)
  local options = copy(DEFAULT_PARSER_OPTIONS)
  opts = opts or EMPTY_T
  for key in pairs(options) do
    local v = opts[key]
    if v ~= nil then
      options[key] = v
    end
  end
  return options
end


local function get_base_path(spec)
  local base_path = "/"
  if spec.openapi then
    -- openapi
    if spec.servers and #spec.servers == 1 and spec.servers[1].url then
      local url = spec.servers[1].url
      if string_byte(url, 1) == SLASH_BYTE then
        base_path = url
      else
        -- fully-qualified URL http://example.com/v1
        local parsed_url = socket_url.parse(url)
        if parsed_url and parsed_url.path and
          string_byte(parsed_url.path, 1) == SLASH_BYTE then
          base_path = parsed_url.path
        end
      end
    end

  else
    -- swagger
    if spec.basePath and
      string_byte(spec.basePath, 1) == SLASH_BYTE then
      base_path = spec.basePath
    end
  end

  return base_path
end

local function remove_trailing_slashes(path)
  local idx
  for i = #path, 1, -1 do
    if string_byte(path, i) ~= SLASH_BYTE then
      break
    end
    idx = i
  end
  if idx then
    path = string_sub(path, 1, idx - 1)
  end
  return path
end

local function resolve_paths(spec)
  local base_path = get_base_path(spec)
  if base_path == "/" or not spec.paths then
    -- do nothing
    return
  end

  local paths = {}
  base_path = remove_trailing_slashes(base_path)
  for path, path_spec in pairs(spec.paths) do
    if string_byte(path, 1) ~= SLASH_BYTE then
      path = "/" .. path
    end
    local resolved_path = base_path .. path
    paths[resolved_path] = path_spec
  end
  spec.paths = paths
end


local function apply(spec, options)
  options = resolve_options(options)

  if options.resolve_base_path == true then
    resolve_paths(spec)
  end

end


return {
  apply = apply
}
