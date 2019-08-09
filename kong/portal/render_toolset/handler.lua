local table_methods   = require("kong.portal.render_toolset.base.table")
local string_methods  = require("kong.portal.render_toolset.base.string")
local number_methods  = require("kong.portal.render_toolset.base.number")
local boolean_methods = require("kong.portal.render_toolset.base.boolean")


local base   = require("kong.portal.render_toolset.base")
local page   = require("kong.portal.render_toolset.page")
local kong   = require("kong.portal.render_toolset.kong")
local user   = require("kong.portal.render_toolset.user")
local theme = require("kong.portal.render_toolset.theme")
local portal = require("kong.portal.render_toolset.portal")


local initializers = {
  ["base"]   = base,
  ["page"]   = page,
  ["kong"]   = kong,
  ["user"]   = user,
  ["theme"]  = theme,
  ["portal"] = portal,
}


local base_helpers = {
  ["table"]   = table_methods,
  ["string"]  = string_methods,
  ["number"]  = number_methods,
  ["boolean"] = boolean_methods,
}


local function reset(self)
  self = {
    ctx         = "__unset__",
    next        = self.next,
    reset       = self.reset,
    set_ctx     = self.set_ctx,
    add_methods = self.add_methods,
  }
  local  mt = {}
  mt.__index = mt
  mt.__call = function(t)
    if t.ctx == "__unset__" then
      t.ctx = nil
    end

    return t.ctx
  end

  setmetatable(self, mt)
end


local function set_ctx(self, ctx)
  if ctx ~= nil then
    self.ctx = ctx
  end

  local ctx_type = type(ctx)
  local base_methods = base_helpers[ctx_type] or {}
  self:add_methods(base_methods)

  return self
end


local function add_methods(self, methods)
  for k, method in pairs(methods) do
    self[k] = function(self, ...)
      if self.ctx == nil then
        return self
      end

      return method(self, ...)
    end
  end
end


local function next(self, method_sets)
  if method_sets then
    self:reset()

    for _, set in ipairs(method_sets) do
      self:add_methods(set)
    end
  end

  return self:set_ctx()
end


local function initiator(type, ...)
  local initializers = initializers[type]

  local helper = {
    ctx         = "__unset__",
    next        = next,
    reset       = reset,
    set_ctx     = set_ctx,
    add_methods = add_methods,
  }

  local  mt = {}
  mt.__index = mt
  mt.__call = function(t)
    if t.ctx == "__unset__" then
      t.ctx = nil
    end

    return t.ctx
  end

  setmetatable(helper, mt)

  helper:add_methods(initializers)

  if helper.setup then
    helper:setup(...)
  end

  return helper
end


return {
  new = function(type)
    return function(...)
      return initiator(type, ...)
    end
  end
}
