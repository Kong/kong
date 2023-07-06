-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local meta = require "kong.meta"
local mime_parse = require "kong.plugins.mocking.mime_parse"
local mocker = require "kong.plugins.mocking.jsonschema-mocker.mocker"
local swagger_parser = require "kong.enterprise_edition.openapi.plugins.swagger-parser.parser"
local constants = require "kong.plugins.mocking.constants"

local ngx = ngx
local kong = kong
local gsub = string.gsub
local match = string.match
local lower = string.lower
local random = math.random
local table_sort = table.sort
local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs
local type = type
local tonumber = tonumber

local EMPTY = {}

local METHODS = {
  get = true,
  post = true,
  put = true,
  patch = true,
  delete = true,
  head = true,
  options = true,
  trace = true,
}


local MockingHandler = {}

MockingHandler.VERSION = meta.core_version
MockingHandler.PRIORITY = -1 -- Mocking plugin should execute after all other plugins

local conf_cache = setmetatable({}, {__mod = "k"})


local function retrieve_operation(spec, path, method)
  if spec.spec.paths then
    for spec_path, path_value in pairs(spec.spec.paths) do
      local formatted_path = gsub(spec_path, "[-.]", "%%%1")
      formatted_path = "^" .. gsub(formatted_path, "{(.-)}", "[A-Za-z0-9._-]+") .. "$"
      if match(path, formatted_path) then
        return path_value[string.lower(method)]
      end
    end
  end
end


local function retrieve_mocking_response_v2(response, accept, code, conf, behavioral_headers)
  local mocking_response = {
    code = tonumber(code),
    content_type = constants.DEFAULT_CONTENT_TYPE,
  }

  if response.examples then
    local examples = response.examples
    if #response._mime_types > 0 then
      local mime_type = mime_parse.best_match(response._mime_types, accept)
      if mime_type ~= "" then
        mocking_response.example = examples[mime_type]
        mocking_response.content_type = mime_type
      end
    end

  elseif response.schema then
    local example = mocker.mock(response.schema)
    mocking_response.example = example

  end
  return mocking_response
end


local function retrieve_mocking_response_v3(response, accept, code, conf, behavioral_headers)
  local content = response.content or {}

  if #response._mime_types == 0 then
    -- does not contain any MIME type
    return { code = tonumber(code), content_type = constants.DEFAULT_CONTENT_TYPE }
  end

  local mime_type = mime_parse.best_match(response._mime_types, accept)
  if mime_type ~= "" then
    local mocking_response = {
      example = nil,
      code = tonumber(code),
      content_type = mime_type
    }

    local example = content[mime_type].example
    local examples = content[mime_type].examples
    local schema = content[mime_type].schema
    if example then
      mocking_response.example = example
    else
      if examples then
        local examples_keys = {}
        for key, _ in pairs(examples) do
          table_insert(examples_keys, key)
        end
        if #examples_keys > 0 then
          if behavioral_headers.example_id then
            local expected_example = examples[behavioral_headers.example_id]
            if expected_example == nil then
              local mocking_error = {
                code = 400,
                message = "could not find the example id '" .. behavioral_headers.example_id .. "'"
              }
              return nil, mocking_error
            end
            mocking_response.example = expected_example.value

          else
            local idx = conf.random_examples and random(1, #examples_keys) or 1
            mocking_response.example = examples[examples_keys[idx]].value
          end
        end

      else
        mocking_response.example = mocker.mock(schema)
      end
    end

    return mocking_response
  end
end


local function retrieve_mocking_response(version, operation, accept, conf, behavioral_headers)
  if operation == nil or operation.responses == nil then
    return nil, nil
  end

  local sorted_codes = operation._sorted_response_codes
  if #sorted_codes == 0 then
    return nil
  end

  -- at least one HTTP status
  local code = conf.random_status_code and sorted_codes[random(1, #sorted_codes)] or sorted_codes[1]
  if behavioral_headers.status_code then
    local expected_status_code = behavioral_headers.status_code
    if operation.responses[expected_status_code] == nil then
      local mocking_error = {
        code = 400,
        message = "could not find the status code '" .. expected_status_code .. "'"
      }
      return nil, mocking_error
    end

    code = expected_status_code
  end

  local target_response = operation.responses[code]

  if version == 3 then
    return retrieve_mocking_response_v3(target_response, accept, code, conf, behavioral_headers)
  end

  return retrieve_mocking_response_v2(target_response, accept, code, conf, behavioral_headers)
end


local function load_content(conf)
  if type(conf.api_specification) == "string" and #conf.api_specification > 0 then
    return conf.api_specification, nil
  end

  if kong.configuration.database == "off" then
    return nil, "The api_specification_filename is not supported in dbless mode, use api_specification instead"
  end

  -- load from files
  local specfile, err = kong.db.files:select_by_path("specs/" .. conf.api_specification_filename)
  if err then
    kong.log.err(err)
    return nil, "An unexpected error happened"
  end
  if specfile == nil then
    return nil, "The API Specification file '" ..
      conf.api_specification_filename .. "' defined in config.api_specification_filename is not found"
  end
  return specfile.contents or ""
end

local function normalize_key(t)
  if type(t) ~= "table" then
    return t
  end
  local t2 = {}
  for k, v in pairs(t) do
    t2[tostring(k)] = v
  end
  return t2
end

local function get_sorted_codes(responses, included_codes)
  local codes = {}
  local included_code_set = {}
  for _, code in ipairs(included_codes or EMPTY) do
    included_code_set[code] = true
  end
  for code, _ in pairs(responses or EMPTY) do
    if included_codes == nil or included_code_set[tonumber(code)] then
      table_insert(codes, code)
    end
  end
  table_sort(codes, function(o1, o2)
    return tonumber(o1) < tonumber(o2)
  end)
  return codes
end

local function normalize_spec(version, spec, conf)
  for _, path in pairs(spec.paths or EMPTY) do -- iterate paths
    for key, method in pairs(path or EMPTY) do -- iterate method
      if not METHODS[lower(key)] then
        goto continue
      end
      method.responses = normalize_key(method.responses) -- normalize the codes
      method._sorted_response_codes = get_sorted_codes(method.responses, conf.included_status_codes)
      for code, response in pairs(method.responses or EMPTY) do -- iterate responses
        if version == 3 then
          local mime_types = {}
          for name, mime_type in pairs(response.content or EMPTY) do
            table_insert(mime_types, name)
            -- normalize the example id
            mime_type.examples = normalize_key(mime_type.examples)
          end
          response._mime_types = mime_types -- makes a cached array
        else
          local mime_types = {}
          for name, mime_type in pairs(response.examples or EMPTY) do
            table_insert(mime_types, name)
          end
          response._mime_types = mime_types -- makes a cached array
        end
      end
      ::continue::
    end
  end
  return spec
end


function MockingHandler:access(conf)
  local path = kong.request.get_path()
  local method = kong.request.get_method()
  local behavioral_headers = {}
  for k, v in pairs(constants.BEHAVIORAL_HEADER_NAMES) do
    behavioral_headers[k] = kong.request.get_header(v)
  end

  local accept = kong.request.get_header("Accept")
  if accept == nil or accept == "*/*" then
    accept = "application/json"
  end

  local spec = conf_cache[conf]
  if not spec then
    local content, err = load_content(conf)
    if err then
      return kong.response.exit(500, { message = err })
    end

    spec, err = swagger_parser.parse(content)
    if err then
      kong.log.err("failed to parse specification: ", err)
      return kong.response.exit(500, { message = "An unexpected error happened" })
    end
    local normalized_spec = normalize_spec(spec.version, spec.spec, conf)
    spec.spec = normalized_spec
    conf_cache[conf] = spec
  end

  local spec_operation = retrieve_operation(spec, path, method)
  if spec_operation == nil then
    return kong.response.exit(404, { message = "Corresponding path and method spec does not exist in API Specification" })
  end

  local mocking_response, mocking_error = retrieve_mocking_response(spec.version, spec_operation, accept, conf, behavioral_headers)
  if mocking_error then
    return kong.response.exit(mocking_error.code, { message = mocking_error.message })
  end

  if mocking_response == nil then
    return kong.response.exit(404, { message = "No examples exist in API specification for this resource matching Accept Header (" .. accept .. ")" })
  end

  if behavioral_headers.delay ~= nil then
    local delay = tonumber(behavioral_headers.delay)
    if delay == nil or delay < 0 or delay > 10000 then
      return kong.response.exit(400, { message = "Invalid value for " .. constants.BEHAVIORAL_HEADER_NAMES.delay ..
        ". The delay value should be a number between 0 and 10000" })
    end
    ngx.sleep(delay / 1000)

  else
    if conf.random_delay then
      ngx.sleep(random(conf.min_delay_time, conf.max_delay_time))
    end
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
