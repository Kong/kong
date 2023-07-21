-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_tablex = require "pl.tablex"
local split = require("pl.utils").split
local constants = require "kong.plugins.oas-validation.constants"

local re_match = ngx.re.match

local EMPTY_T = pl_tablex.readonly({})
local ipairs = ipairs
local fmt = string.format
local type = type
local gsub = string.gsub
local tostring = tostring
local CONTENT_METHODS = constants.CONTENT_METHODS

local _M = {}

local COMMON_FILE_FORMAT_SEPARATOR = {
  csv = {
    seperator = ",",
  },
  ssv = {
    seperator = " ",
  },
  tsv = {
    seperator = "\\",
  },
  pipes = {
    seperator = "|",
  },
}

local RE_EMAIL = "[a-zA-Z][\\w\\_]{6,15})\\@([a-zA-Z0-9.-]+)\\.([a-zA-Z]{2,4}"
local RE_UUID  = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

local OPEN_API = "openapi"


local function to_wildcard_subtype(content_type)
  -- remove parameter in content type
  return gsub(content_type, "([^/]+)/([^/]+)", "%1") .. "/*"
end


-- @param body_spec Specification of the request/response body.
-- @param content_type Content-Type of the request/response body.
-- @return Schema of the request/response body if succeeed, nil otherwise.
local function locate_content_schema_by_content_type(media_types, media_type)
  local schema
  if media_types then
    schema = (media_types[media_type] and media_types[media_type].schema) or
             (media_types[to_wildcard_subtype(media_type)] and media_types[to_wildcard_subtype(media_type)].schema) or
             (media_types["*/*"] and media_types["*/*"].schema)
  end
  return schema
end

function _M.locate_request_body_schema(request_body_spec, content_type)
  local schema

  if request_body_spec then
    schema = locate_content_schema_by_content_type(request_body_spec.content, content_type)
  end

  if not schema then
    return nil, fmt("no request body schema found for content type '%s'", content_type)
  end

  return schema
end


function _M.locate_response_body_schema(spec_version, method_spec, status_code, content_type)
  if not (method_spec and method_spec.responses) then
   return nil, "no response schema defined in api specification"
  end

  local schema
  -- the HTTP status code field in the Response Object MUST be enclosed in quotation marks (for example, “200”)
  -- for compatibility between JSON and YAML.
  local response = method_spec.responses[tostring(status_code)]
  if spec_version ~= OPEN_API then
    if response then
      schema = response.schema

    elseif method_spec.responses.default then
      schema = method_spec.responses.default
    end

  elseif response and response.content then
    schema = locate_content_schema_by_content_type(response.content, content_type)
  end

  if not schema then
    return nil, fmt("no response body schema found for status code '%s' and content type '%s'",
                              status_code, content_type)
  end

  return schema
end


local function find_param(params, name, locin)
  if not params then
    return false
  end

  for _, param in ipairs(params) do
    if param["name"] == name and param["in"] == locin then
      return true, param
    end
  end

  return false
end


-- Merge method-level parameters into path-level parameters
-- Method-level parameter should override path parameter if they share same name and location value
function _M.merge_params(path_params, method_params)
  if path_params == nil or #path_params == 0 then
    -- returns method-level parameters if path-level parameters is empty
    return method_params
  end

  local merged_params = {}
  local n = 0
  for _, param in ipairs(path_params or EMPTY_T) do
    local found, method_param = find_param(method_params, param["name"], param["in"])
    n = n + 1
    if found then
      -- method-level parameter can override path-level parameter
      merged_params[n] = method_param
    else
      merged_params[n] = param
    end
  end

  -- add other method parameters
  for _, param in ipairs(method_params or EMPTY_T) do
    local found = find_param(merged_params, param["name"], param["in"])
    if not found then
      n = n + 1
      merged_params[n] = param
    end
  end

  return merged_params
end


function _M.parameter_validator_v2(parameter)
  if parameter.type == "string" and parameter.format == "email" then
    if not re_match(parameter.value, RE_EMAIL) then
      return false, "parameter value is not a valid email address"
    end

  elseif parameter.format == "uuid" and not re_match(parameter.value, RE_UUID) then
      return false, "parameter value does not match UUID format"
  end

  return true
end


function _M.param_array_helper(parameter)
  local format = parameter.collectionFormat
  if not format then
    return nil
  end

  if format == "multi" and type(parameter.value) == "string" then
    return {parameter.value}
  end

  return split(parameter.value, COMMON_FILE_FORMAT_SEPARATOR[format].seperator, true)
end


function _M.parameter_schema_check(parameter)
  local location = parameter["in"]

  if not location then
    return false, "no parameter.in field exists in specification"
  end

  if not parameter["name"] then
    return false, "no parameter.name field exists in specification"
  end

  if parameter.schema and parameter.content then
    return false, "either parameter.schema or parameter.content allowed, not both"
  end

  if not parameter.schema then
    if not parameter.type then
      return false, "no parameter.type exists in specification"
    end

    if parameter.type == "array" and not parameter.items then
      return false, "parameter.items is required if parameter.style is 'array'"
    end
  end
end


function _M.content_type_allowed(content_type, method, method_spec)
  if content_type ~= "application/json" then
    return false, "content-type '" .. content_type .. "' is not supported"
  end

  if CONTENT_METHODS[method] then
    if method_spec.consumes then
      local content_types = method_spec.consumes
      if type(content_types) ~= "table" then
        content_types = { content_types }
      end

      local cmp = function(e, v) return e:lower() == v:lower() and e end
      if not pl_tablex.find_if(content_types, cmp, content_type) then
        return false, fmt("content type '%s' does not exist in specification", content_type)
      end
    end
  end

  return true
end


return _M
