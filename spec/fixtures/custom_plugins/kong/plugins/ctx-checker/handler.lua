local BasePlugin = require "kong.plugins.base_plugin"


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
  if ctx[set_field] and conf.throw_error then
    error("Expected to be able to set" ..
          conf.ctx_kind,
          "['" .. set_field ..
          "'] but it was already set. Found value: " ..
          tostring(ctx[set_field]))
  end
  ctx[set_field] = conf.ctx_set_value
end


function CtxCheckerHandler:header_filter(conf)
  CtxCheckerHandler.super.header_filter(self)

  local check_field = conf.ctx_check_field
  if not check_field then
    return
  end

  local ctx = get_ctx(conf.ctx_kind)

  if not conf.ctx_check_value or ctx[check_field] == conf.ctx_check_value then
    set_header(conf,
               self._name .. "-" .. check_field,
               ctx[check_field])
  end

  if conf.throw_error then
    error("Expected " .. conf.ctx_kind .. "['" ..
          check_field .. "'] to be set, but it was " .. tostring(ctx[check_field]))

  end
end


return CtxCheckerHandler
