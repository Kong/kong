-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe"

local sandbox     = require "kong.tools.sandbox"
local workspaces  = require "kong.workspaces"

local PLUGIN_NAME    = require("kong.plugins.exit-transformer").PLUGIN_NAME
local PLUGIN_VERSION = require("kong.plugins.exit-transformer").PLUGIN_VERSION


local function get_conf()
  local conf = kong.ctx.shared.exit_transformer_conf

  if not conf then
    -- Our access handler was not run, which implies the request did not match
    -- any route. If a global instance of this plugin is configured on the
    -- current workspace then we can consult this to see if `handle_unknown`
    -- has been specified.

    -- Look for a global plugin instance for this workspace
    local cache_key = kong.db.plugins:cache_key(
      PLUGIN_NAME,
      nil, -- route
      nil, -- service
      nil, -- consumer
      nil, -- (unused)
      workspaces.get_workspace_id()
    )

    local _, _, global_plugin = kong.core_cache:probe(cache_key)
    if global_plugin and global_plugin.config.handle_unknown then
      conf = global_plugin.config
    end
  end

  if conf and ngx.ctx.KONG_UNEXPECTED and not conf.handle_unexpected then
    return nil
  end

  return conf
end

local _M = {}

_M.PRIORITY = 9999
_M.VERSION = PLUGIN_VERSION

function _M:init_worker()
  kong.response.register_hook("exit", self.exit, self)
  kong.response.register_hook("send", self.exit, self)
end


local function_cache = setmetatable({}, { __mode = "k" })

local function no_op(err)
  return function(status, body, headers)
    kong.log.err(err)
    return status, body, headers
  end
end

local function get_functions(conf)
  if function_cache[conf] then return function_cache[conf] end

  local functions = {}

  local sandbox_opts = { env = { kong = kong } }

  for _, fn_str in ipairs(conf.functions) do
    local f, err = sandbox.validate_function(fn_str, sandbox_opts)
    if err then f = no_op(err) end

    table.insert(functions, f)
  end

  function_cache[conf] = functions

  return functions
end

function _M:access(conf)
  -- register our plugin conf with the request context so that it is available
  -- during the `exit` hook.
  kong.ctx.shared.exit_transformer_conf = conf
end

function _M:exit(status, body, headers)
  -- Do not transform already transformed requests
  if ngx.ctx.exit_transformed then
    return status, body, headers
  end

  -- Do not transform admin requests
  if not ngx.ctx.is_proxy_request then
    return status, body, headers
  end

  -- Try to get plugin configuration for current context
  local conf = get_conf()

  if not conf then
    return status, body, headers
  end

  -- XXX Both exit and send now contain body as plaintext always
  -- try to convert back to message and if that fails give it raw
  local data, err = cjson.decode(body)

  if not err then
    body = data
  end

  local functions = get_functions(conf)

  -- Reduce on status, body, headers through transform functions
  for _, fn in ipairs(functions) do
    status, body, headers = fn(status, body, headers)
  end

  ngx.ctx.exit_transformed = true

  return status, body, headers
end

return _M
