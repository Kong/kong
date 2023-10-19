-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local dereference = require "kong.enterprise_edition.openapi.plugins.swagger-parser.dereference"
local options = require "kong.enterprise_edition.openapi.plugins.swagger-parser.options"
local cjson = require("cjson.safe").new()
local lyaml = require "lyaml"

local type = type
local pcall = pcall
local fmt = string.format
local tab_sort = table.sort
local pairs = pairs

local _M = {}

-- Dereference spec
-- @param spec
-- @param opts options.DEFAULT_OPTIONS
_M.dereference = function(spec, opts)
  opts = options.resolve_options(opts)
  return dereference.resolve(spec, opts)
end

--- Parse spec
-- @param spec_str
-- @param opts options.DEFAULT_OPTIONS
_M.parse = function(spec_str, opts)
  spec_str = ngx.unescape_uri(spec_str)
  local parsed_spec, decode_err = cjson.decode(spec_str)
  if decode_err then
    -- fallback to YAML
    local pok
    pok, parsed_spec = pcall(lyaml.load, spec_str)
    if not pok or type(parsed_spec) ~= "table" then
      return nil, fmt("api specification is neither valid json ('%s') nor valid yaml ('%s')",
        decode_err, parsed_spec)
    end
  end

  opts = options.resolve_options(opts)
  local deferenced_schema, err = dereference.resolve(parsed_spec, opts)
  if err then
    return nil, err
  end

  options.apply(deferenced_schema, opts)

  -- sort paths for later path matching
  if deferenced_schema.paths then
    local sorted_paths = {}
    local n = 0
    for path in pairs(deferenced_schema.paths) do
      n = n + 1
      sorted_paths[n] = path
    end

    tab_sort(sorted_paths)
    deferenced_schema.sorted_paths = sorted_paths
  end


  local spec = {
    spec = deferenced_schema,
    version = 2
  }
  if parsed_spec.openapi then
    spec.version = 3
  end

  return spec, nil
end


return _M
