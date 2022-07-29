-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson.safe").new()
local meta = require "kong.meta"
local lyaml = require "lyaml"
local mime_parse = require "kong.plugins.mocking.mime_parse"

local ngx = ngx
local kong = kong
local gsub = string.gsub
local match = string.match
local random = math.random

local MockingHandler = {}

MockingHandler.VERSION = meta.core_version
MockingHandler.PRIORITY = -1 -- Mocking plugin should execute after all other plugins

local DEFAULT_CONTENT_TYPE = "application/json; charset=utf-8"

local is_present = function(v)
  return type(v) == "string" and #v > 0
end

--- Parse OpenAPI specification.
local function parse_specification(spec_content)
  kong.log.debug("parsing specification: \n", spec_content)

  local parsed_spec, decode_err = cjson.decode(spec_content)
  if decode_err then
    -- fallback to YAML
    local pok
    pok, parsed_spec = pcall(lyaml.load, spec_content)
    if not pok or type(parsed_spec) ~= "table" then
      return nil, string.format("Spec is neither valid json ('%s') nor valid yaml ('%s')",
        decode_err, parsed_spec)
    end
  end

  local spec = {
    spec = parsed_spec,
    version = 2
  }
  if parsed_spec.openapi then
    spec.version = 3
  end

  return spec
end

local function retrieve_operation(spec, path, method)
  if spec.spec.paths then
    for spec_path, path_value in pairs(spec.spec.paths) do
      local formatted_path = gsub(spec_path, "[-.]", "%%%1")
      formatted_path = gsub(formatted_path, "{(.-)}", "[A-Za-z0-9]+") .. "$"
      if match(path, formatted_path) then
        return path_value[string.lower(method)]
      end
    end
  end
end

local function find_key(tbl, key)
  for lk, lv in pairs(tbl) do
    if lk == key then
      return lv
    end
    if type(lv) == "table" then
      for dk, dv in pairs(lv) do
        if dk == key then
          return dv
        end
        if type(dv) == "table" then
          for ek, ev in pairs(dv) do
            if ek == key then
              return ev
            end
          end
        end
      end
    end
  end

  return nil
end

local function get_sorted_codes(responses)
  local codes = {}
  for code, _ in pairs(responses) do
    table.insert(codes, code)
  end
  table.sort(codes, function(o1, o2)
    return tonumber(o1) < tonumber(o2)
  end)
  return codes
end

local function retrieve_mocking_response_v2(operation, accept)
  if operation == nil or operation.responses == nil then
    return nil
  end

  local responses = operation.responses
  local sorted_codes = get_sorted_codes(responses)
  if #sorted_codes == 0 then
    return nil
  end

  -- at least one code exist
  local code = sorted_codes[1]
  local target_response = responses[code]
  local examples = target_response.examples or {}
  local supported_mime_types = {}
  for type, _ in pairs(examples) do
    table.insert(supported_mime_types, type)
  end

  if #supported_mime_types == 0 then
    -- does not contain any MIME type
    return { code = tonumber(code), content_type = DEFAULT_CONTENT_TYPE }
  end

  local mime_type = mime_parse.best_match(supported_mime_types, accept)
  if mime_type ~= "" then
    return {
      example = examples[mime_type],
      code = tonumber(code),
      content_type = mime_type
    }
  end

  return nil
end

local function retrieve_mocking_response_v3(operation, accept, conf, params)
  if operation == nil or operation.responses == nil then
    return nil
  end

  local responses = operation.responses
  local sorted_codes = get_sorted_codes(responses)
  if #sorted_codes == 0 then
    return nil
  end

  local code = sorted_codes[1]
  local target_response = responses[code]
  local content = target_response.content or {}
  local supported_mime_types = {}
  for type, _ in pairs(content) do
    table.insert(supported_mime_types, type)
  end

  if #supported_mime_types == 0 then
    -- does not contain any MIME type
    return { code = tonumber(code), content_type = DEFAULT_CONTENT_TYPE }
  end

  local mime_type = mime_parse.best_match(supported_mime_types, accept)
  if mime_type ~= "" then
    local mocking_response = {
      example = nil,
      code = tonumber(code),
      content_type = mime_type
    }

    local example = content[mime_type].example
    local examples = content[mime_type].examples
    if example then
      mocking_response.example = example
    else
      if examples then
        -- [[ filter examples by params
        if params and next(params) ~= nil then
          local qualified_example_keys = {}
          for param_name, param_value in pairs(params) do
            for example_key, example_value in pairs(examples) do
              local field_value = find_key(example_value.value, param_name)
              if type(param_value) == "string" then
                if field_value and string.lower(field_value) == string.lower(param_value) then
                  table.insert(qualified_example_keys, example_key)
                end
              end
            end
          end
          if #qualified_example_keys > 0 then
            local exmaples_copy = {}
            for _, key in ipairs(qualified_example_keys) do
              exmaples_copy[key] = examples[key]
            end
            examples = exmaples_copy
          end
        end
        --]]

        local examples_keys = {}
        for key, _ in pairs(examples) do
          table.insert(examples_keys, key)
        end
        if #examples_keys > 0 then
          if conf.random_examples then
            mocking_response.example = examples[examples_keys[random(1, #examples_keys)]].value
          else
            mocking_response.example = examples[examples_keys[1]].value
          end
        end
      end
    end

    return mocking_response
  end

  return nil
end

function MockingHandler:access(conf)
  local path = kong.request.get_path()
  local method = kong.request.get_method()

  local accept = kong.request.get_header("Accept")
  if accept == nil or accept == "*/*" then
    accept = "application/json"
  end

  local content
  if is_present(conf.api_specification) then
    content = conf.api_specification

  else
    if kong.db == nil then
      return kong.response.exit(500, { message = "API Specification file api_specification_filename defined which is not supported in dbless mode - not supported. Use api_specification instead" })
    end
    local specfile, err = kong.db.files:select_by_path("specs/" .. conf.api_specification_filename)
    if err then
      kong.log.err(err)
      return kong.response.exit(500, { message = "An unexpected error happened" })
    end
    if specfile == nil then
      return kong.response.exit(500, { message = "The API Specification file '" ..
        conf.api_specification_filename .. "' which is defined in api_specification_filename is not found" })
    end
    content = specfile.contents or ""

  end

  local spec, err = parse_specification(content)
  if err then
    kong.log.err("failed to parse specification: ", err)
    return kong.response.exit(500, { message = "An unexpected error happened" })
  end

  local spec_operation = retrieve_operation(spec, path, method)
  if spec_operation == nil then
    return kong.response.exit(404, { message = "Path does not exist in API Specification" })
  end

  local mocking_response
  if spec.version == 3 then
    local params = kong.request.get_query(1000)
    mocking_response = retrieve_mocking_response_v3(spec_operation, accept, conf, params)
  else
    mocking_response = retrieve_mocking_response_v2(spec_operation, accept, conf)
  end

  if mocking_response == nil then
    return kong.response.exit(404, { message = "No examples exist in API specification for this resource with Accept Header (" .. accept .. ")" })
  end

  if conf.random_delay then
    ngx.sleep(random(conf.min_delay_time, conf.max_delay_time))
  end

  local headers = nil
  if mocking_response.content_type then
    headers = { ["Content-Type"] = mocking_response.content_type }
  end

  return kong.response.exit(mocking_response.code, mocking_response.example, headers)
end

function MockingHandler:header_filter(conf)
  kong.response.add_header("X-Kong-Mocking-Plugin", "true")
end

return MockingHandler
