-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_template = require "pl.template"
local pl_tablex = require "pl.tablex"
local math_floor = math.floor

local set_path = kong.service.request.set_path
local req_get_headers = ngx.req.get_headers
local req_get_uri_args = ngx.req.get_uri_args
local meta = require "kong.meta"

local error = error
local rawset = rawset

local template_environment

local EMPTY = pl_tablex.readonly({})


-- meta table for the sandbox, exposing lazily loaded values
local __meta_environment = {
  __index = function(self, key)
    local lazy_loaders = {
      headers = function(self)
        return req_get_headers() or EMPTY
      end,
      query_params = function(self)
        return req_get_uri_args() or EMPTY
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
  rawset(template_environment, "headers", nil)
  rawset(template_environment, "query_params", nil)
  rawset(template_environment, "uri_captures", nil)
  rawset(template_environment, "shared", nil)
end



local plugin = {
  VERSION  = meta.core_version,
  PRIORITY = 780,
}

local conf_cache = setmetatable({}, {
  __mode = "k",
  __index = function(self, conf)
    -- from the configuration we compile the templates, and generate functions
    local funcs = {}

    if conf.path then
      local tmpl = assert(pl_template.compile(conf.path))
      funcs[#funcs+1] = function(env)
        local new_value, err = tmpl:render(env)
        if not new_value then
          kong.log.err("failed to render path template: ", err)
          return kong.response.exit(500)
        end

        if conf.escape_path then
          set_path(new_value)
        else
          ngx.var.upstream_uri = new_value
        end
      end
    end

    if conf.host then
      local tmpl = assert(pl_template.compile(conf.host))
      funcs[#funcs+1] = function(env)
        local new_value, err = tmpl:render(env)
        if not new_value then
          kong.log.err("failed to render host template: ", err)
          return kong.response.exit(500)
        end

        ngx.ctx.balancer_data.host = new_value
      end
    end

    if conf.port then
      local tmpl = assert(pl_template.compile(conf.port))
      funcs[#funcs+1] = function(env)
        local new_value, err = tmpl:render(env)
        if not new_value then
          kong.log.err("failed to render port template: ", err)
          return kong.response.exit(500)
        end

        local new_port = tonumber(new_value)
        if not new_port then
          kong.log.err("failed to render port template, returned: ", new_value)
          return kong.response.exit(500)
        end

        ngx.ctx.balancer_data.port = math_floor(new_port)
      end
    end

    return funcs
  end,
})

function plugin:access(conf)
  local funcs = conf_cache[conf] -- fetch cached compiled functions

  clear_environment()
  for _, func in ipairs(funcs) do
    func(template_environment)
  end
end


return plugin
