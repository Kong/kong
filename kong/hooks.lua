local _M = {}


local hooks = {}


local ipairs = ipairs
local pack = table.pack
local unpack = table.unpack
local insert = table.insert


local function wrap_hook(f)
   return function(acc, ...)
      if acc and not acc[1] then
         return acc
      end
      return pack(f(...))
   end
end


-- Register a hook function.
-- @param name Name of the hook; names should be namespaced
-- so that they don't conflict: e.g. "dao:upsert:pre"
-- @param hook Hook function, which receives the arguments
-- passed to run_hook(). By default, if a previous hook function
-- returned nil, the hook function will not execute and
-- the return values from the previous one will be returned as
-- the result of run_hook().
-- @param opts Table of options:
-- * "low_level" - if true, hook is assumed to be a "low-level hook
--   function": the low-level function receives an array in
--   table.pack() format as the first argument and is expected
--   to return a similar array. It can decide to run even if
--   a previous hook failed.
function _M.register_hook(name, hook, opts)
  assert(type(hook) == "function", "hook must be a function")

  hooks[name] = hooks[name] or {}

  local f
  if opts and opts.low_level then
    f = hook
  else
    f = wrap_hook(hook)
  end

  insert(hooks[name], f)
end


function _M.run_hook(name, ...)
  if not hooks[name] then
    return (...) -- return only the first value
  end

  local acc

  for _, f in ipairs(hooks[name] or {}) do
    acc = f(acc, ...)
  end

  return unpack(acc, 1, acc.n)
end


function _M.clear_hooks()
  hooks = {}
end


return _M
