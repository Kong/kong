-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson                 = require("cjson.safe").new()
local generator             = require("kong.tools.json-schema.draft4").generate
local pl_tablex             = require "pl.tablex"
local pl_stringx            = require "pl.stringx"
local deserialize           = require "resty.openapi3.deserializer"
local split                 = require("pl.utils").split
local normalize             = require("kong.tools.uri").normalize
local event_hooks           = require "kong.enterprise_edition.event_hooks"
local clone                 = require "table.clone"
local meta                  = require "kong.meta"

local common_utils          = require "kong.plugins.oas-validation.utils.common"
local validation_utils      = require "kong.plugins.oas-validation.utils.validation"
local spec_parser           = require "kong.plugins.oas-validation.utils.spec_parser"

local get_req_body_json           = common_utils.get_req_body_json
local extract_media_type          = common_utils.extract_media_type
local get_spec_from_conf          = spec_parser.get_spec_from_conf
local get_method_spec             = spec_parser.get_method_spec
local content_type_allowed        = validation_utils.content_type_allowed
local is_body_method              = validation_utils.is_body_method
local param_array_helper          = validation_utils.param_array_helper
local merge_params                = validation_utils.merge_params
local parameter_validator_v2      = validation_utils.parameter_validator_v2
local locate_request_body_schema  = validation_utils.locate_request_body_schema
local locate_response_body_schema = validation_utils.locate_response_body_schema

local kong                  = kong
local ngx                   = ngx
local re_match              = ngx.re.match
local ipairs                = ipairs
local fmt                   = string.format
local json_decode           = cjson.decode
local json_encode           = cjson.encode
local EMPTY                 = pl_tablex.readonly({})
local find                  = pl_tablex.find
local replace               = pl_stringx.replace


cjson.decode_array_with_array_mt(true)

local DENY_REQUEST_MESSAGE = "request doesn't conform to schema"
local DENY_PARAM_MESSAGE = "request param doesn't conform to schema"
local DENY_RESPONSE_MESSAGE = "response doesn't conform to schema"
local DEFAULT_CONTENT_TYPE = "application/json"

local OPEN_API = "openapi"


local OASValidationPlugin = {
  VERSION  = meta.core_version,
  -- priority after security & rate limiting plugins
  PRIORITY = 850,
}


-- meta table for the sandbox, exposing lazily loaded values
local template_environment
local __meta_environment = {
  __index = function(self, key)
    local lazy_loaders = {
      header = function(self)
        return kong.request.get_headers() or EMPTY
      end,
      query = function(self)
        return kong.request.get_query() or EMPTY
      end,
      path = function(self)
        return split(string.sub(normalize(kong.request.get_path(),true), 2),"/") or EMPTY
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

template_environment = setmetatable({
}, __meta_environment)


local function clear_environment()
  rawset(template_environment, "header", nil)
  rawset(template_environment, "query", nil)
  rawset(template_environment, "path", nil)
end


local validator_cache = setmetatable({}, {
  __mode = "k",
  __index = function(self, parameter)
      -- it was not found, so here we generate it
      local validator_func = assert(generator(json_encode(parameter.schema)))
      self[parameter] = validator_func
    return validator_func
  end
})


local validator_param_cache = setmetatable({}, {
  __mode = "k",
  __index = function(self, parameter)
    -- it was not found, so here we generate it
    local validator_func = assert(generator(json_encode(parameter.schema), {
      coercion = true,
    }))
    parameter.decoded_schema = assert(parameter.schema)
    self[parameter] = validator_func
    return validator_func
  end
})


local function validate_style_deepobject(location, parameter)

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
local function need_validate_parameter(parameter, conf)
  if parameter["in"] == "header" and not conf.validate_request_header_params then
    return false
  end

  if parameter["in"] == "query" and not conf.validate_request_query_params then
    return false
  end

  if parameter["in"] == "path" and not conf.validate_request_uri_params then
    return false
  end

  if parameter["in"] == "body" and not conf.validate_request_body and conf.parsed_spec.swagger then
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
  local value
  local location = parameter["in"]
  if location == "body" then
    value = get_req_body_json() or EMPTY

  elseif location == "path" then
    -- find location of parameter in the specification
    local uri_params = split(string.sub(path_spec,2),"/")
    for idx, name in ipairs(uri_params) do
      if re_match(name, parameter.name) then
        value = template_environment[location][idx]
        break
      end
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
  for qname, _ in pairs(template_environment[location]) do
    local exists = false
    for _, parameter in pairs(spec_params) do
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


local function validate_error_handler(conf, errcode, errmsg, default_errmsg, log_level)
  emit_event_hook(errmsg)

  local log_level = log_level or "err"
  -- no need to return error
  if errcode == nil then
    kong.log[log_level](errmsg)
    return
  end

  -- need to return response error with errcode
  if conf.verbose_response then
    return kong.response.exit(errcode, { message = errmsg })

  else
    return kong.response.exit(errcode, { message = default_errmsg })
  end
end


function OASValidationPlugin:init_worker()

  -- register validation event hook
  event_hooks.publish("oas-validation", "validation-failed", {
    fields = { "consumer", "ip", "service", "err" },
    unique = { "consumer", "ip", "service" },
    description = "Run an event when oas validation fails",
  })

end


function OASValidationPlugin:response(conf)
  if not conf.validate_response_body then
    return
  end

  -- do not validate if the request is not originated from the proxied service
  if kong.response.get_source() ~= "service" then
    return
  end

  local body = kong.service.response.get_raw_body()
  local resp_status_code = kong.service.response.get_status()

  local content_type_header = kong.service.response.get_header("Content-Type")
  local content_type = extract_media_type(content_type_header) or DEFAULT_CONTENT_TYPE

  local method_spec = ngx.ctx.method_spec or get_method_spec(conf, ngx.ctx.resp_uri, ngx.ctx.resp_method)
  local schema, err = locate_response_body_schema(conf.parsed_spec.swagger or OPEN_API, method_spec, resp_status_code, content_type)

  -- no response schema found, skip validation
  if not schema then
    return validate_error_handler(conf, nil, err, err, "notice")
  end

  local parameter = { schema = schema }
  local validator = validator_cache[parameter]
  local resp_obj = json_decode(body)
  --check response type
  if parameter.schema.type == "array" and type(resp_obj) == "string" then
    resp_obj = {resp_obj}
  end

  if parameter.schema.type == "array" and type(resp_obj) == "table" then
    setmetatable(resp_obj, cjson.array_mt)
  end

  local ok, err = validator(resp_obj)
  if not ok then
    local errmsg = fmt("response body validation failed with error: %s", replace(err, "userdata", "null"))
    if conf.notify_only_response_body_validation_failure then
      return validate_error_handler(conf, nil, errmsg, errmsg, "err")

    else
      return validate_error_handler(conf, 406, errmsg, DENY_RESPONSE_MESSAGE, "err")
    end
  end
end


function OASValidationPlugin:access(conf)

  clear_environment()

  local method = kong.request.get_method()
  local path = normalize(kong.request.get_path(), true)
  if conf.validate_response_body then
    -- used ngx.ctx instead of kong.ctx since kong.ctx used in response phase is not thread safe
    ngx.ctx.resp_uri = path
    ngx.ctx.resp_method = method
  end

  local content_type_header = kong.request.get_header("Content-Type")
  local content_type = extract_media_type(content_type_header) or DEFAULT_CONTENT_TYPE

  local method_spec, path_spec, path_params, err = get_spec_from_conf(conf, path, method)
  if not method_spec then
    local errmsg = fmt("validation failed, %s", err)
    if conf.notify_only_request_validation_failure then
      return validate_error_handler(conf, nil, errmsg, errmsg, "err")

    else
      return validate_error_handler(conf, 400, errmsg, DENY_REQUEST_MESSAGE, "err")
    end
  end
  ngx.ctx.method_spec = method_spec

  -- check content-type matches the spec
  local ok, err = content_type_allowed(content_type, method, method_spec)
  if not ok then
    local errmsg = fmt("validation failed: %s", err)
    if conf.notify_only_request_validation_failure then
      return validate_error_handler(conf, nil, errmsg, errmsg, "err")

    else
      return validate_error_handler(conf, 400, errmsg, DENY_REQUEST_MESSAGE, "err")
    end
  end

  --merge path and method level parameters
  --method level parameters take precedence over path
  local merged_params
  if path_params then
    merged_params = merge_params(path_params, method_spec.parameters)

  else
    merged_params = method_spec.parameters
  end

  if conf.header_parameter_check then
    local ok, err = check_parameter_existence(merged_params or EMPTY, "header", conf.allowed_header_parameters)
    if not ok then
      local errmsg = fmt("validation failed with error: %s", err)
      if conf.notify_only_request_validation_failure then
        return validate_error_handler(conf, nil, errmsg, errmsg, "err")

      else
        return validate_error_handler(conf, 400, errmsg, DENY_PARAM_MESSAGE, "err")
      end
    end
  end

  -- check if query & headers in request exist in spec
  if conf.query_parameter_check then
    local ok, err = check_parameter_existence(merged_params or EMPTY, "query")
    if not ok then
      local errmsg = fmt("validation failed with error: %s", err)
      if conf.notify_only_request_validation_failure then
        return validate_error_handler(conf, nil, errmsg, errmsg, "err")

      else
        return validate_error_handler(conf, 400, errmsg, DENY_PARAM_MESSAGE, "err")
      end
    end
  end

  for _, parameter in ipairs(merged_params or EMPTY) do
    -- Shortcuts for skipping paramter validation
    if not need_validate_parameter(parameter, conf) then
      goto skip_paramter_validation
    end

    -- Parameter validation
    local ok, err = validate_parameters(parameter, path_spec, conf.parsed_spec.swagger or OPEN_API)
    if not ok then
      -- check for userdata cjson.null and return nicer err message
      local errmsg = fmt("%s '%s' validation failed with error: '%s'", parameter["in"],
                                      parameter.name, replace(err, "userdata", "null"))
      if conf.notify_only_request_validation_failure then
        return validate_error_handler(conf, nil, errmsg, errmsg, "err")

      else
        return validate_error_handler(conf, 400, errmsg, DENY_PARAM_MESSAGE, "err")
      end
    end

    ::skip_paramter_validation::
  end

  -- validate oas body if required
  if conf.validate_request_body and conf.parsed_spec.openapi and is_body_method(method) then
    local res_schema, errmsg = locate_request_body_schema(method_spec, content_type)

    if not res_schema then
      if conf.notify_only_request_validation_failure then
        return validate_error_handler(conf, nil, errmsg, errmsg, "err")

      else
        return validate_error_handler(conf, 400, errmsg, DENY_PARAM_MESSAGE, "err")
      end
    end

    local parameter = {
      schema = res_schema
    }
    local validator = validator_cache[parameter]
    -- validate request body against schema
    local ok, err = validator(get_req_body_json() or EMPTY)

    if not ok then
      -- check for userdata cjson.null and return nicer err message
      local errmsg = fmt("request body validation failed with error: '%s'", replace(err, "userdata", "null"))
      if conf.notify_only_request_validation_failure then
        return validate_error_handler(conf, nil, errmsg, errmsg, "err")

      else
        return validate_error_handler(conf, 400, errmsg, DENY_PARAM_MESSAGE, "err")
      end
    end
  end
end


return OASValidationPlugin

