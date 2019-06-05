local BasePlugin = require "kong.plugins.base_plugin"
local tablex = require "pl.tablex"
local inspect = require "inspect"


local ngx = ngx
local kong = kong
local type = type
local error = error
local tostring = tostring


local CtxCheckerHandler = BasePlugin:extend()


CtxCheckerHandler.PRIORITY = 1000


local function get_ctx(ctx_kind)
  if ctx_kind == "kong.ctx.shared" then
    return kong.ctx.shared
  end

  if ctx_kind == "kong.ctx.plugin" then
    return kong.ctx.plugin
  end

  return ngx.ctx
end


local function set_header(conf, name, value)
  if conf.ctx_kind == "kong.ctx.shared"
  or conf.ctx_kind == "kong.ctx.plugin" then
    return kong.response.set_header(name, value)
  end

  ngx.header[name] = value
end


function CtxCheckerHandler:new()
  CtxCheckerHandler.super.new(self, "ctx-checker")
end


function CtxCheckerHandler:access(conf)
  CtxCheckerHandler.super.access(self)

  local set_field = conf.ctx_set_field
  if not set_field then
    return
  end

  local ctx = get_ctx(conf.ctx_kind)
  local existing = ctx[set_field]
  if existing ~= nil and conf.throw_error then
    if type(existing) == "table" then
      existing = inspect(existing)
    end

    error("Expected to be able to set" ..
          conf.ctx_kind ..
          "['" .. set_field ..
          "'] but it was already set. Found value: " ..
          tostring(existing))
  end


  if type(conf.ctx_set_array) == "table" then
    ctx[set_field] = conf.ctx_set_array
  elseif type(conf.ctx_set_value) == "string" then
    ctx[set_field] = conf.ctx_set_value
  end
end


function CtxCheckerHandler:header_filter(conf)
  CtxCheckerHandler.super.header_filter(self)

  local check_field = conf.ctx_check_field
  if not check_field then
    return
  end

  local ctx = get_ctx(conf.ctx_kind)
  local val = ctx[check_field]

  local ok
  if conf.ctx_check_array then
    if type(val) == "table" then
      ok = tablex.compare(val, conf.ctx_check_array, "==")
    else
      ok = false
    end

  elseif conf.ctx_check_value then
    ok = val == conf.ctx_check_value
  else
    ok = true
  end

  if type(val) == "table" then
    val = inspect(val)
  end

  if ok then
    return set_header(conf, self._name .. "-" .. check_field, tostring(val))
  end

  if conf.throw_error then
    error("Expected " .. conf.ctx_kind .. "['" .. check_field ..
          "'] to be set, but it was " .. tostring(val))
  end
end


return CtxCheckerHandler
