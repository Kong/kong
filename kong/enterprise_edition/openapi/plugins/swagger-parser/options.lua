-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_tablex = require "pl.tablex"
local socket_url = require "socket.url"

local type = type
local pairs = pairs
local string_byte = string.byte
local string_sub = string.sub
local deepcopy = pl_tablex.deepcopy

local SLASH_BYTE = string_byte("/")
local EMPTY_T = {}

local DEFAULT_OPTIONS = {
  resolve_base_path = false,
  custom_base_path = "",
  dereference = {
    maximum_dereference = 0
  },
}


local function merge(opts, customize_opts)
  for k, v in pairs(opts) do
    if type(v) == "table" and type(customize_opts[k]) == "table" then
      merge(v, customize_opts[k])
    else
      if customize_opts[k] ~= nil then
        opts[k] = customize_opts[k]
      end
    end
  end
  return opts
end


local function resolve_options(opts)
  local default_options = deepcopy(DEFAULT_OPTIONS)
  return merge(default_options, opts or EMPTY_T)
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
  return #path ~= 0 and path
end

local function get_base_path(spec)
  if spec.openapi then
    -- openapi
    if spec.servers and #spec.servers > 0 then
      local base_paths = {}
      local i = 1
      for _, server in pairs(spec.servers) do
        local url, formatted_url = server.url
        if string_byte(url, 1) == SLASH_BYTE then
          formatted_url = remove_trailing_slashes(url)
        else
          -- fully-qualified URL http://example.com/v1
          local parsed_url = socket_url.parse(url)
          if parsed_url and parsed_url.path and
            string_byte(parsed_url.path, 1) == SLASH_BYTE then
              formatted_url = remove_trailing_slashes(parsed_url.path)
          end
        end
        if formatted_url and not base_paths[formatted_url] then
          base_paths[formatted_url] = true
          base_paths[i] = formatted_url
          i = i + 1
        end
      end

      return base_paths
    end

  else
    -- swagger
    if spec.basePath and
      string_byte(spec.basePath, 1) == SLASH_BYTE then
      return { spec.basePath }
    end
  end
end

local function resolve_path(spec, custom_base_path)
  if custom_base_path and custom_base_path ~= "" then
    spec.base_paths = { remove_trailing_slashes(custom_base_path) }
  else
    spec.base_paths = get_base_path(spec) or {'/'}
  end
end


local function apply(spec, options)
  if options.resolve_base_path == true then
    resolve_path(spec, options.custom_base_path)
  end

end


return {
  apply = apply,
  resolve_options = resolve_options,
}
