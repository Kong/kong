local cjson = require("cjson.safe").new()
local lrucache = require "resty.lrucache"
local pl_tablex = require "pl.tablex"
local BasePlugin = require "kong.plugins.base_plugin"
local deserialize = require "resty.openapi3.deserializer"

local EMPTY = pl_tablex.readonly({})
local DENY_BODY_MESSAGE = "request body doesn't conform to schema"
local DENY_PARAM_MESSAGE = "request param doesn't conform to schema"

local kong = kong
local json_decode = cjson.decode
local ngx_req_read_body = ngx.req.read_body
local ngx_req_get_body_data = ngx.req.get_body_data
local req_get_headers = ngx.req.get_headers
local req_get_uri_args = ngx.req.get_uri_args
local ipairs = ipairs
local setmetatable = setmetatable
local ngx_null = ngx.null
local type = type
local string_find = string.find
local ngx_re_match = ngx.re.match


cjson.decode_array_with_array_mt(true)


local content_type_allowed
do
  local media_type_pattern = [[(.+)\/([^ ;]+)]]
  local conf_cache = setmetatable({}, {
    __mode = "k",
    __index = function(self, plugin_config)
      -- create if not found
      local conf = {}
      conf.lru = assert(lrucache.new(500))
      conf.arr = {}
      for _, value in ipairs(plugin_config.allowed_content_types) do
        local matches = assert(ngx_re_match(value:lower(),
                                            media_type_pattern, "ajo"))
        conf.arr[#conf.arr + 1] = matches
      end
      -- store for future use an return
      self[plugin_config] = conf
      return conf
    end
  })

  function content_type_allowed(plugin_config, content_type)
    local conf = conf_cache[plugin_config]
    if not content_type then
      return false
    end
    -- test our cache
    local allowed = conf.lru:get(content_type)
    if allowed ~= nil then
      return allowed
    end
    -- nothing in cache, try and parse
    local matches = ngx_re_match(content_type:lower(),
                                 media_type_pattern, "ajo")
    if not matches then
      -- parse failure, so not allowed
      allowed = false
    else
      -- iterate our list of allowed values
      allowed = false
      for i = 1, #conf.arr do
        local type = conf.arr[i][1]
        local subtype = conf.arr[i][2]
        if (type == "*" or matches[1] == type) and
           (subtype == "*" or matches[2] == subtype) then
          allowed = true
          break
        end
      end
    end
    -- store in cache
    conf.lru:set(content_type, allowed)
    return allowed
  end
end


-- meta table for the sandbox, exposing lazily loaded values
-- todo use pdk
local template_environment
local __meta_environment = {
  __index = function(self, key)
    local lazy_loaders = {
      header = function(self)
        return req_get_headers() or EMPTY
      end,
      query = function(self)
        return req_get_uri_args() or EMPTY
      end,
      path = function(self)
        return (ngx.ctx.router_matches or EMPTY).uri_captures or EMPTY
      end,
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
  -- here we can optionally add functions to expose to the sandbox, eg:
  -- tostring = tostring,  -- for example
}, __meta_environment)


local function clear_environment()
  rawset(template_environment, "header", nil)
  rawset(template_environment, "query", nil)
  rawset(template_environment, "path", nil)
end


local validator_cache = setmetatable({}, {
  __mode = "k",
  __index = function(self, plugin_config)
      -- it was not found, so here we generate it
      local generator = require("kong.plugins.request-validator." ..
        plugin_config.version).generate
      local validator_func = assert(generator(plugin_config.body_schema))
      self[plugin_config] = validator_func
    return validator_func
  end
})


local validator_param_cache = setmetatable({}, {
  __mode = "k",
  __index = function(self, parameter)
    -- it was not found, so here we generate it
    local generator = require("kong.plugins.request-validator.draft4").generate
    local validator_func = assert(generator(parameter.schema, {
      coercion = true,
    }))
    parameter.decoded_schema = assert(json_decode(parameter.schema))
    self[parameter] = validator_func
    return validator_func
  end
})


local function get_req_body_json()
  ngx_req_read_body()

  local body_data = ngx_req_get_body_data()
  if not body_data or #body_data == 0 then
    return {}
  end

  -- try to decode body data as json
  local body, err = json_decode(body_data)
  if err then
    return nil, "request body is not valid JSON"
  end

  return body
end


local function validate_required(location, parameter)
  if location == "query" and parameter.style == "deepObject" then
    return true
  end

  local value = template_environment[location][parameter.name]
  if parameter.required and value == nil then
    return false
  end

  parameter.value = value
  return true
end


local function validate_style_deepobject(location, parameter)

  local validator = validator_param_cache[parameter]

  local result, err =  deserialize(parameter.style, parameter.decoded_schema.type,
          parameter.explode, parameter.name, template_environment[location])
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


local function validate_data(location, parameter)
  if location == "query" and parameter.style == "deepObject" then
    return validate_style_deepobject(location, parameter)
  end

  -- if param is not required and value is nil or serialization
  -- information not being set, return valid
  if not parameter.value or parameter.style == ngx_null  then
    return true
  end

  local validator = validator_param_cache[parameter]
  local result, err =  deserialize(parameter.style, parameter.decoded_schema.type,
          parameter.explode, parameter.value)
  if err or not result then
    return false
  end

  -- temporary, deserializer should return correct table
  if parameter.decoded_schema.type == "array" and type(result) == "table" then
    setmetatable(result, cjson.array_mt)
  end

  return validator(result)
end


local validate_parameters = {
  path = function(parameter)
    if not validate_required("path", parameter) or
            not validate_data("path", parameter) then
      return false
    end

    return true
  end,

  header = function(parameter)
    if not validate_required("header", parameter) or
            not validate_data("header", parameter) then
      return false
    end

    return true
  end,

  query = function(parameter)
    if not validate_required("query", parameter) or
            not validate_data("query", parameter) then
      return false
    end

    return true
  end,
}


local RequestValidator = BasePlugin:extend()
RequestValidator.PRIORITY = 200
RequestValidator.VERSION = "0.2.0"


function RequestValidator:new()
  RequestValidator.super.new(self, "request-validator")
end


function RequestValidator:access(conf)
  RequestValidator.super.access(self)

  -- validate parameters
  clear_environment()
  for _, parameter in ipairs(conf.parameter_schema or EMPTY) do
    local ok = validate_parameters[parameter["in"]](parameter)
    if not ok then
      return kong.response.exit(400, { message = DENY_PARAM_MESSAGE })
    end
  end

  if conf.body_schema then
    local content_type = kong.request.get_header("content-type")
    if not content_type_allowed(conf, content_type) then
      return kong.response.exit(400, { message = DENY_BODY_MESSAGE })
    end

    if not string_find(content_type, "application/json") then
      return
    end

    -- try to retrieve cached request body schema entity
    -- if it isn't in cache, it will be created
    local validator = validator_cache[conf]

    local body, err = get_req_body_json()
    if not body then
      return kong.response.exit(400, err)
    end

    -- try to validate body against schema
    local ok, _ = validator(body)
    if not ok then
      return kong.response.exit(400, { message = DENY_BODY_MESSAGE })
    end
  end

end

RequestValidator.PRIORITY = 999
RequestValidator.VERSION = "0.3.0"

return RequestValidator
