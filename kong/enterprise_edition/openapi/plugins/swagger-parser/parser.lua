-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local dereference = require "kong.enterprise_edition.openapi.plugins.swagger-parser.dereference"
local cjson = require("cjson.safe").new()
local lyaml = require "lyaml"

local type = type
local pcall = pcall
local fmt = string.format

local _M = {}

_M.dereference = function(schema)
  return dereference.dereference(schema)
end

_M.parse = function(spec_content)
  local parsed_spec, decode_err = cjson.decode(spec_content)
  if decode_err then
    -- fallback to YAML
    local pok
    pok, parsed_spec = pcall(lyaml.load, spec_content)
    if not pok or type(parsed_spec) ~= "table" then
      return nil, fmt("Spec is neither valid json ('%s') nor valid yaml ('%s')",
        decode_err, parsed_spec)
    end
  end

  local deferenced_schema, err = _M.dereference(parsed_spec)
  if err then
    return nil, err
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
