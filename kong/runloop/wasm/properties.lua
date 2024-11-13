local _M = {}

local clear_tab = require "table.clear"

local kong = kong
local ngx = ngx


local simple_getters = {}
local simple_setters = {}
local namespace_handlers = {}

local get_namespace, rebuild_namespaces
do
  local patterns = {}
  local handlers = {}
  local namespaces_len = 0

  function rebuild_namespaces()
    clear_tab(patterns)
    clear_tab(handlers)

    for ns, handler in pairs(namespace_handlers) do
      table.insert(patterns, ns .. ".")
      table.insert(handlers, handler)
    end

    namespaces_len = #patterns
  end

  local find = string.find
  local sub = string.sub

  ---@param property string
  ---@return table? namespace
  ---@return string? key
  function get_namespace(property)
    for i = 1, namespaces_len do
      local from, to = find(property, patterns[i], nil, true)
      if from == 1 then
        local key = sub(property, to + 1)
        return handlers[i], key
      end
    end
  end
end


function _M.reset()
  clear_tab(simple_getters)
  clear_tab(simple_setters)
  clear_tab(namespace_handlers)
  rebuild_namespaces()
end


function _M.add_getter(name, handler)
  assert(type(name) == "string")
  assert(type(handler) == "function")

  simple_getters[name] = handler
end


function _M.add_setter(name, handler)
  assert(type(name) == "string")
  assert(type(handler) == "function")

  simple_setters[name] = handler
end


function _M.add_namespace_handlers(name, get, set)
  assert(type(name) == "string")
  assert(type(get) == "function")
  assert(type(set) == "function")

  namespace_handlers[name] = { get = get, set = set }
  rebuild_namespaces()
end


---@param name string
---@return boolean? ok
---@return string? value_or_error
---@return boolean? is_const
function _M.get(name)
  local ok, value, const = false, nil, nil

  local getter = simple_getters[name]
  if getter then
    ok, value, const = getter(kong, ngx, ngx.ctx)

  else
    local ns, key = get_namespace(name)

    if ns then
      ok, value, const = ns.get(kong, ngx, ngx.ctx, key)
    end
  end

  return ok, value, const
end


---@param name string
---@param value string|nil
---@return boolean? ok
---@return string? cached_value
---@return boolean? is_const
function _M.set(name, value)
  local ok, cached_value, const = false, nil, nil

  local setter = simple_setters[name]
  if setter then
    ok, cached_value, const = setter(kong, ngx, ngx.ctx, value)

  else
    local ns, key = get_namespace(name)
    if ns then
      ok, cached_value, const = ns.set(kong, ngx, ngx.ctx, key, value)
    end
  end

  return ok, cached_value, const
end


return _M
