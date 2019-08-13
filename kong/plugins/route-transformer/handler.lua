local pl_template = require "pl.template"
local pl_tablex = require "pl.tablex"

local req_get_headers = ngx.req.get_headers
local req_get_uri_args = ngx.req.get_uri_args

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



local route_transformer = {
  VERSION  = "0.1.0",
  PRIORITY = 800,
}

local conf_cache = setmetatable({}, {
  __mode = "k",
  __index = function(self, conf)
    -- from the configuration we compile the templates, and generate functions
    local funcs = {}

    if conf.path then
      local tmpl = assert(pl_template.compile(conf.path))
      funcs[#funcs+1] = function(env)
        ngx.var.upstream_uri = assert(tmpl:render(env))
      end
    end

    if conf.host then
      local tmpl = assert(pl_template.compile(conf.host))
      funcs[#funcs+1] = function(env)
        ngx.ctx.balancer_address.host = assert(tmpl:render(env))
      end
    end

    if conf.port then
      local tmpl = assert(pl_template.compile(conf.port))
      funcs[#funcs+1] = function(env)
        ngx.ctx.balancer_address.port = assert(tonumber(assert(tmpl:render(env))))
      end
    end

    return funcs
  end,
})

function route_transformer:access(conf)
  local funcs = conf_cache[conf] -- fetch cached compiled functions

  clear_environment()
  for _, func in ipairs(funcs) do
    func(template_environment)
  end
end


return route_transformer
