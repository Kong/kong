local http = require "resty.http"
local clone = require "table.clone"
local sandbox = require "kong.tools.sandbox"
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy
local pl_template = require "pl.template"
local lua_enabled = sandbox.configuration.enabled
local sandbox_enabled = sandbox.configuration.sandbox_enabled
local get_request_headers = kong.request.get_headers
local get_uri_args = kong.request.get_query
local rawset = rawset
local str_find = string.find
local tostring = tostring
local null = ngx.null
local EMPTY = require("kong.tools.table").EMPTY

local CONTENT_TYPE_HEADER_NAME = "Content-Type"
local DEFAULT_CONTENT_TYPE_HEADER = "application/x-protobuf"
local DEFAULT_HEADERS = {
  [CONTENT_TYPE_HEADER_NAME] = DEFAULT_CONTENT_TYPE_HEADER
}

local _log_prefix = "[otel] "

local function http_export_request(conf, pb_data, headers)
  local httpc = http.new()
  httpc:set_timeouts(conf.connect_timeout, conf.send_timeout, conf.read_timeout)
  local res, err = httpc:request_uri(conf.endpoint, {
    method = "POST",
    body = pb_data,
    headers = headers,
  })

  if not res then
    return false, "failed to send request: " .. err

  elseif res and res.status ~= 200 then
    return false, "response error: " .. tostring(res.status) .. ", body: " .. tostring(res.body)
  end

  return true
end


local function get_headers(conf_headers)
  if not conf_headers or conf_headers == null then
    return DEFAULT_HEADERS
  end

  if conf_headers[CONTENT_TYPE_HEADER_NAME] then
    return conf_headers
  end

  local headers = clone(conf_headers)
  headers[CONTENT_TYPE_HEADER_NAME] = DEFAULT_CONTENT_TYPE_HEADER
  return headers
end


local compile_opts = {
  escape = "\xff", -- disable '#' as a valid template escape
}

local template_cache = setmetatable( {}, { __mode = "k" })

local __meta_environment = {
  __index = function(self, key)
    local lazy_loaders = {
      headers = function(self)
        return get_request_headers() or EMPTY
      end,
      query_params = function(self)
        return get_uri_args() or EMPTY
      end,
      uri_captures = function(self)
        return (ngx.ctx.router_matches or EMPTY).uri_captures or EMPTY
      end,
      shared = function(self)
        return ((kong or EMPTY).ctx or EMPTY).shared or EMPTY
      end,
    }
    local loader = lazy_loaders[key]
    if not loader then
      if lua_enabled and not sandbox_enabled then
        return _G[key]
      end
      return
    end
    -- set the result on the table to not load again
    local value = loader()
    rawset(self, key, value)
    return value
  end,
  __newindex = function(self)
    error("This environment is read-only.")
  end,
}


local function param_value(source_template, resource_attributes, template_env)
  if not source_template or source_template == "" then
    return nil
  end

  if not lua_enabled then
    -- Detect expressions in the source template
    local expr = str_find(source_template, "%$%(.*%)")
    if expr then
      return nil, "loading of untrusted Lua code disabled because " ..
                  "'untrusted_lua' config option is set to 'off'"
    end
    -- Lua is disabled, no need to render the template
    return source_template
  end

  -- find compiled templates for this plugin-configuration array
  local compiled_templates = template_cache[resource_attributes]
  if not compiled_templates then
    compiled_templates = {}
    -- store it by `resource_attributes` which is part of the plugin `conf` table
    -- it will be GC'ed at the same time as `conf` and hence invalidate the
    -- compiled templates here as well as the cache-table has weak-keys
    template_cache[resource_attributes] = compiled_templates
  end

  -- Find or compile the specific template
  local compiled_template = compiled_templates[source_template]
  if not compiled_template then
    local res
    compiled_template, res = pl_template.compile(source_template, compile_opts)
    if res then
      return source_template
    end
    compiled_templates[source_template] = compiled_template
  end

  return compiled_template:render(template_env)
end

local function compile_resource_attributes(resource_attributes)
  if not resource_attributes then
    return EMPTY
  end

  local template_env = {}
  if lua_enabled and sandbox_enabled then
    -- load the sandbox environment to be used to render the template
    template_env = cycle_aware_deep_copy(sandbox.configuration.environment)
    -- here we can optionally add functions to expose to the sandbox, eg:
    -- tostring = tostring,
    -- because headers may contain array elements such as duplicated headers
    -- type is a useful function in these cases. See issue #25.
    template_env.type = type
  end
  setmetatable(template_env, __meta_environment)
  local compiled_resource_attributes = {}
  for current_name, current_value in pairs(resource_attributes) do
    local res, err = param_value(current_value, resource_attributes, template_env)
    if not res then
      return nil, err
    end

    compiled_resource_attributes[current_name] = res
  end
  return compiled_resource_attributes
end



return {
  http_export_request = http_export_request,
  get_headers = get_headers,
  _log_prefix = _log_prefix,
  compile_resource_attributes = compile_resource_attributes,
}
