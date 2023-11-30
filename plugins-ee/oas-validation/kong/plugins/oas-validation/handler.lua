-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe".new()
local pl_tablex = require "pl.tablex"
local pl_stringx = require "pl.stringx"
local split = require "pl.utils".split
local deserialize = require "resty.openapi3.deserializer"
local event_hooks = require "kong.enterprise_edition.event_hooks"
local clone = require "table.clone"
local swagger_parser = require "kong.enterprise_edition.openapi.plugins.swagger-parser.parser"
local lrucache = require "resty.lrucache"
local utils = require "kong.plugins.oas-validation.utils"
local validation_utils = require "kong.plugins.oas-validation.utils.validation"
local sha256_hex = require "kong.tools.utils".sha256_hex
local normalize = require "kong.tools.uri".normalize
local generator = require "kong.tools.json-schema.draft4".generate
local parse_mime_type = require "kong.tools.mime_type".parse_mime_type
local meta = require "kong.meta"
local constants = require "kong.plugins.oas-validation.constants"

local kong = kong
local ngx = ngx
local type = type
local setmetatable = setmetatable
local re_match = ngx.re.match
local ipairs = ipairs
local pairs = pairs
local fmt = string.format
local string_sub = string.sub
local gsub = string.gsub
local json_decode = cjson.decode
local json_encode = cjson.encode
local EMPTY_T = pl_tablex.readonly({})
local find = pl_tablex.find
local replace = pl_stringx.replace
local request_get_header = kong.request.get_header

local get_req_body_json = utils.get_req_body_json
local content_type_allowed = validation_utils.content_type_allowed
local param_array_helper = validation_utils.param_array_helper
local merge_params = validation_utils.merge_params
local parameter_validator_v2 = validation_utils.parameter_validator_v2
local locate_request_body_schema = validation_utils.locate_request_body_schema
local locate_response_body_schema = validation_utils.locate_response_body_schema


local spec_cache = lrucache.new(1000)

cjson.decode_array_with_array_mt(true)

local DENY_REQUEST_MESSAGE = "request doesn't conform to schema"
local DENY_PARAM_MESSAGE = "request param doesn't conform to schema"
local DENY_RESPONSE_MESSAGE = "response doesn't conform to schema"
local DEFAULT_CONTENT_TYPE = "application/json"

local OPEN_API = "openapi"

local CONTENT_METHODS = constants.CONTENT_METHODS

local OASValidationPlugin = {
  VERSION  = meta.core_version,
  PRIORITY = 850, -- priority after security & rate limiting plugins
}

local function resolve_schema(schema)
  local metatable = getmetatable(schema)
  if not metatable then
    return schema
  end
  if type(schema.is_ref) == "function" and schema:is_ref() then
    schema.definitions = metatable.refs.definitions
    schema.components = metatable.refs.components
  end
  return schema
end

local validator_cache = setmetatable({}, {
  __mode = "k",
  __index = function(self, parameter)
    -- it was not found, so here we generate it
    local schema = resolve_schema(parameter.schema)
    local json = assert(json_encode(schema))
    local validator_func = assert(generator(json))
    self[parameter] = validator_func
    return validator_func
  end
})


local validator_param_cache = setmetatable({}, {
  __mode = "k",
  __index = function(self, parameter)
    -- it was not found, so here we generate it
    local schema = resolve_schema(parameter.schema)
    local json = assert(json_encode(schema))
    local validator_func = assert(generator(json, {
      coercion = true,
    }))
    parameter.decoded_schema = assert(parameter.schema)
    self[parameter] = validator_func
    return validator_func
  end
})


local function validate_style_deepobject(location, parameter)
  local template_environment = kong.ctx.plugin.template_environment
  local validator = validator_param_cache[parameter]
  local result, err = deserialize(parameter.style, parameter.decoded_schema.type,
          parameter.explode, parameter.name, template_environment[location], location)
  if err == "not found" and not parameter.required then
    return true
  end

  if err or not result then
    return false
  end

  -- temporary, deserializer should return correct table
  if parameter.decoded_schema.type == "array" and type(result) == "table" then
    setmetatable(result, cjson.array_mt)
  end

  return validator(result)
end


-- Check the necessity of the parameter validation
local function need_validate_parameter(parameter, conf, parsed_spec)
  local location = parameter["in"]

  if location == "header" and not conf.validate_request_header_params then
    return false
  end
  if location == "query" and not conf.validate_request_query_params then
    return false
  end
  if location == "path" and not conf.validate_request_uri_params then
    return false
  end
  if location == "body" and not conf.validate_request_body and parsed_spec.swagger then
    return false
  end

  return true
end


local function validate_parameter_value_openapi(parameter)
  if parameter["in"] == "body" then
    local validator = validator_cache[parameter]
    -- try to validate body against schema
    local ok, err = validator(parameter.value)
    if not ok then
      return false, err
    end

    return true

  elseif parameter.style then
    local validator = validator_param_cache[parameter]
    local result, err =  deserialize(parameter.style, parameter.decoded_schema.type,
        parameter.explode, parameter.value, nil, parameter["in"])

    if err or not result then
      return false, err
    end

    if parameter.decoded_schema.type == "array" and type(result) == "table" then
      setmetatable(result, cjson.array_mt)
    end

    local ok, err = validator(result)
    if not ok then
      return false, err
    end

    return true

  else
    if parameter.type == "array" and type(parameter.value) == "string" then
      parameter.value = {parameter.value}
    end

    if parameter.type == "array" and type(parameter.value) == "table" then
      setmetatable(parameter.value, cjson.array_mt)
    end

    local validator = validator_param_cache[parameter]
    local ok, err = validator(parameter.value)
    if not ok then
      return false, err
    end
    return true
  end
end


local function validate_parameter_value_swagger(parameter)
  local parameter_table = clone(parameter)
  -- validate swagger v2 parameters
  local schema = {
    type = parameter_table.type,
    enum = parameter_table.enum,
    items = parameter_table.items,
    pattern = parameter_table.pattern,
    format = parameter_table.format,
    minItems = parameter_table.minItems,
    maxItems = parameter_table.maxItems,
  }
  -- check if value is string for type array
  if parameter_table.type == "array" and type(parameter_table.value) == "string" and parameter_table.collectionFormat then
      parameter_table.value = param_array_helper(parameter_table)
  end
  if parameter_table.type == "array" and type(parameter_table.value) == "table" then
    setmetatable(parameter_table.value, cjson.array_mt)
  end
  parameter_table.schema = schema

  local validator = validator_param_cache[parameter_table]
  local ok, err = validator(parameter_table.value)
  if not ok then
    return false, err
  end

  -- validate v2 param info not supported by ljsonschema
  local ok, err = parameter_validator_v2(parameter_table)
  if not ok then
    return false, err
  end

  return true
end


-- Validate the parameter according to the schema, check if the value is valid
local function validate_parameter_value(parameter, spec_ver)
  local location = parameter["in"]

  if location == "query" and parameter.style == "deepObject" then
    return validate_style_deepobject(location, parameter)
  end

  -- if optional and not in request ignore
  if not parameter.required and parameter.value == nil then
    return true
  end

  if parameter.schema then
    return validate_parameter_value_openapi(parameter)
  elseif spec_ver ~= OPEN_API then
    return validate_parameter_value_swagger(parameter)
  end
end


local function check_required_parameter(parameter, path_spec)
  local template_environment = kong.ctx.plugin.template_environment
  local value
  local location = parameter["in"]
  if location == "body" then
    value = get_req_body_json() or EMPTY_T

  elseif location == "path" then
    local request_path = normalize(kong.request.get_path(), true)
    local path_pattern = gsub(path_spec, "/", "\\/")
    path_pattern = gsub(path_pattern, "{(.-)}", function(str)
      return "(?<" .. str .. ">[^/]+)"
    end)
    local m, err = re_match(request_path, path_pattern)
    if err then
      kong.log.err("failed to match regular expression path: ", path_pattern)
    end
    if m then
      value = m[parameter.name]
    end

  else
    value = template_environment[location][parameter.name]
  end

  if location == "query" and parameter.required and value == nil and not parameter.allowEmptyValue then
    return false, "required parameter value not found in request"
  end

  if location ~= "query" and parameter.required and value == nil then
    return false, "required parameter value not found in request"
  end

  parameter.value = value
  return true
end


local function validate_parameters(parameter, path, spec_ver)
  local ok, err = check_required_parameter(parameter, path)
  if not ok then
    return false, err
  end

  local ok, err = validate_parameter_value(parameter, spec_ver)
  if not ok then
    return false, err
  end

  return true
end


-- check parameters existence according to their location
local function check_parameter_existence(spec_params, location, allowed)
  local template_environment = kong.ctx.plugin.template_environment
  for qname, _ in pairs(template_environment[location]) do
    local exists = false
    for _, parameter in pairs(spec_params or EMPTY_T) do
      if parameter["in"] == location and qname:lower() == parameter.name:lower() then
        exists = true
        break
      end
    end

    if not exists and allowed and find(split(allowed:lower(), ","), qname:lower()) then
      exists = true
    end

    if not exists then
      return false, fmt("%s parameter '%s' does not exist in specification", location, qname)
    end
  end

  return true
end


local function emit_event_hook(errmsg)

  event_hooks.emit("oas-validation", "validation-failed", {
    consumer = kong.client.get_consumer() or {},
    ip = kong.client.get_forwarded_ip(),
    service = kong.router.get_service() or {},
    err = errmsg,
  })

end


local function handle_validate_error(err, default_message, http_code, options)
  options = options or EMPTY_T

  emit_event_hook(err)

  if options.interrupt_request then
    local message = options.verbose and err or default_message
    kong.response.exit(http_code, { message = message })
    return
  end

  local level = options.log_level or "err"
  kong.log[level](err)
end


function OASValidationPlugin:init_worker()
  -- register validation event hook
  event_hooks.publish("oas-validation", "validation-failed", {
    fields = { "consumer", "ip", "service", "err" },
    unique = { "consumer", "ip", "service" },
    description = "Run an event when oas validation fails",
  })
end



local function extract_media_type(content_type)
  if content_type then
    local media_type, media_subtype = parse_mime_type(content_type)
    if media_type and media_subtype then
      return media_type .. "/" .. media_subtype
    end
  end
  return DEFAULT_CONTENT_TYPE
end


function OASValidationPlugin:response(conf)
  if not conf.validate_response_body then
    return
  end
  -- do not validate if the request is not originated from the proxied service
  if kong.response.get_source() ~= "service" then
    return
  end

  local data = ngx.ctx._oas_validation_data or EMPTY_T

  local resp_status_code = kong.service.response.get_status()

  local content_type = extract_media_type(kong.service.response.get_header("Content-Type"))

  local schema, err = locate_response_body_schema(data.spec_version or OPEN_API, data.spec_method, resp_status_code, content_type)

  -- no response schema found, skip validation
  if not schema then
    return handle_validate_error(err, nil, nil, {
      verbose = conf.verbose_response,
      interrupt_request = false, -- does not interrupt the request flow
      log_level = "notice",
    })
  end

  local parameter = { schema = schema }
  local validator = validator_cache[parameter]
  local resp_obj = json_decode(kong.service.response.get_raw_body())
  --check response type
  if parameter.schema.type == "array" and type(resp_obj) == "string" then
    resp_obj = {resp_obj}
  end

  if parameter.schema.type == "array" and type(resp_obj) == "table" then
    setmetatable(resp_obj, cjson.array_mt)
  end

  local ok, err = validator(resp_obj)
  if not ok then
    err = fmt("response body validation failed with error: %s", replace(err, "userdata", "null"))
    return handle_validate_error(err, DENY_RESPONSE_MESSAGE, 406, {
      verbose = conf.verbose_response,
      interrupt_request = not conf.notify_only_response_body_validation_failure,
      log_level = "err",
    })
  end
end



local function parse_spec(conf)
  local spec_content = conf.api_spec
  -- includes conf.include_base_path as part of the cache key
  -- as it could lead to a different parsed result.
  local spec_cache_key = fmt("%s:%s",
                             sha256_hex(spec_content),
                             conf.include_base_path)
  local parsed_spec = spec_cache:get(spec_cache_key)
  if not parsed_spec then
    local opts = {
      resolve_base_path = conf.include_base_path,
      dereference = { circular = true },
    }
    spec_content = ngx.unescape_uri(spec_content)
    local spec, err = swagger_parser.parse(spec_content, opts)
    if err then
      return nil, err
    end

    -- converting nullable keyword
    utils.traverse(spec, "nullable", function(key, value, parent)
      if value == true then
        local t = parent["type"]
        if type(t) == "string" then
          parent["type"] = { t, "null" } -- inject "null"
        end
      end
    end)

    parsed_spec = spec.spec
    spec_cache:set(spec_cache_key, parsed_spec)
  end
  return parsed_spec
end

local function init_template_environment()
  -- meta table for the sandbox, exposing lazily loaded values
  local __meta_environment = {
    __index = function(self, key)
      local lazy_loaders = {
        header = function(self)
          return kong.request.get_headers() or EMPTY_T
        end,
        query = function(self)
          return kong.request.get_query() or EMPTY_T
        end,
        path = function(self)
          return split(string_sub(normalize(kong.request.get_path(),true), 2),"/") or EMPTY_T
        end
      }
      local loader = lazy_loaders[key]
      if not loader then
        -- we don't have a loader, so just return nothing
        return
      end
      -- set the result on the table to not load again
      local value = loader()
      rawset(self, key, value)
      return value
    end,
    __new_index = function(self)
      error("This environment is read-only.")
    end,
  }

  return setmetatable({}, __meta_environment)
end


function OASValidationPlugin:access(conf)
  kong.ctx.plugin.template_environment = init_template_environment()

  local request_method = kong.request.get_method()
  local request_path = normalize(kong.request.get_path(), true)
  local error_options = {
    verbose = conf.verbose_response,
    interrupt_request = not conf.notify_only_request_validation_failure,
  }

  local plugin_data = {}
  if conf.validate_response_body then
    ngx.ctx._oas_validation_data = plugin_data
  end

  local parsed_spec, err = parse_spec(conf)
  if err then
    err = "validation failed, Unable to parse the api specification: " .. err
    return handle_validate_error(err, DENY_REQUEST_MESSAGE, 400, error_options)
  end

  local path_spec, match_path, method_spec = utils.retrieve_operation(parsed_spec, request_path, request_method)
  if not method_spec then
    local err = "validation failed, path not found in api specification"
    return handle_validate_error(err, DENY_REQUEST_MESSAGE, 400, error_options)
  end

  plugin_data.spec_method = method_spec
  plugin_data.spec_version = parsed_spec.swagger

  local parameters = method_spec.parameters or {}
  if path_spec.parameters then
    -- injects path level parameters
    -- https://swagger.io/docs/specification/describing-parameters/#path-parameters [Common Parameters]
    parameters = merge_params(path_spec.parameters, parameters)
  end

  if conf.header_parameter_check then
    local ok, err = check_parameter_existence(parameters, "header", conf.allowed_header_parameters)
    if not ok then
      err = fmt("validation failed with error: %s", err)
      return handle_validate_error(err, DENY_PARAM_MESSAGE, 400, error_options)
    end
  end

  -- check if query & headers in request exist in spec
  if conf.query_parameter_check then
    local ok, err = check_parameter_existence(parameters, "query")
    if not ok then
      err = fmt("validation failed with error: %s", err)
      return handle_validate_error(err, DENY_PARAM_MESSAGE, 400, error_options)
    end
  end

  -- check content-type matches the spec
  local content_type = extract_media_type(request_get_header("Content-Type"))
  -- vars are lazy used
  local content_type_check, content_type_check_err = content_type_allowed(content_type, request_method, method_spec)


  for _, parameter in ipairs(parameters) do
    if need_validate_parameter(parameter, conf, parsed_spec) then
      if parameter["in"] == "body" and not content_type_check then
        err = fmt("validation failed: %s", content_type_check_err)
        return handle_validate_error(err, DENY_REQUEST_MESSAGE, 400, error_options)
      end
      local ok, err = validate_parameters(parameter, match_path, parsed_spec.swagger or OPEN_API)
      if not ok then
        -- check for userdata cjson.null and return nicer err message
        err = fmt("%s '%s' validation failed with error: '%s'", parameter["in"],
          parameter.name, replace(err, "userdata", "null"))
        return handle_validate_error(err, DENY_PARAM_MESSAGE, 400, error_options)
      end
    end
  end

  -- validate oas body if required
  local request_body = method_spec.requestBody
  if conf.validate_request_body and parsed_spec.openapi and CONTENT_METHODS[request_method] and request_body then
    if not content_type_check then
      err = fmt("validation failed: %s", content_type_check_err)
      return handle_validate_error(err, DENY_REQUEST_MESSAGE, 400, error_options)
    end

    local res_schema, err = locate_request_body_schema(request_body, content_type)

    if not res_schema then
      return handle_validate_error(err, DENY_PARAM_MESSAGE, 400, error_options)
    end

    local parameter = {
      schema = res_schema
    }
    local validator = validator_cache[parameter]
    -- validate request body against schema
    local ok, err = validator(get_req_body_json() or EMPTY_T)
    if not ok then
      -- check for userdata cjson.null and return nicer err message
      err = fmt("request body validation failed with error: '%s'", replace(err, "userdata", "null"))
      return handle_validate_error(err, DENY_PARAM_MESSAGE, 400, error_options)
    end
  end

end


return OASValidationPlugin

