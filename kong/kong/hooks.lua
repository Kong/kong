local _M = {}


local hooks = {}


local ipairs = ipairs
local pack = table.pack
local unpack = table.unpack
local insert = table.insert
local type = type
local select = select
local EMPTY = require("kong.tools.table").EMPTY

--[[
  The preferred maximum number of return values from a hook,
  which can avoid the performance issue of using `...` (varargs),
  because calling a function with `...` is NYI in LuaJIT,
  and NYI will abort the trace that impacts the performance.

  This value should large enough to cover the majority of the cases,
  and small enough to avoid the performance overhead to pass too many
  arguments to the hook functions.

  IF YOU CHANGE THIS VALUE, MAKE SURE YOU CHECK ALL THE PLACE
  THAT USES THIS VALUE TO MAKE SURE IT'S SAFE TO CHANGE.
  THE PLACE THAT USES THIS VALUE SHOULD LOOK LIKE THIS:

  ```
  -- let's assume PREFERED_MAX_HOOK_RETS is 4
  if retc <= PREFERED_MAX_HOOK_RETS then
    local r0, r1, r2, r3 = unpack(retv, 1, retc)
    return r0, r1, r2, r3
  end
  ```
--]]
local PREFERED_MAX_HOOK_RETS = 4


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


function _M.run_hook(name, a0, a1, a2, a3, a4, a5, ...)
  if not hooks[name] then
    return a0 -- return only the first value
  end

  local acc

  -- `select` only JIT-able when first argument 
  -- is a constant (Has to be positive if used with varg).
  local extra_argc = select("#", ...)

  for _, f in ipairs(hooks[name] or EMPTY) do
    if extra_argc == 0 then
      --[[
        This is the reason that we don't use the `...` (varargs) here,
        because calling a function with `...` is NYI in LuaJIT,
        and NYI will abort the trace that impacts the performance.
      --]]
      acc = f(acc, a0, a1, a2, a3, a4, a5)

    else
      acc = f(acc, a0, a1, a2, a3, a4, a5, ...)
    end
  end

  if type(acc) == "table"          and
     type(acc.n) == "number"       and
     acc.n <= PREFERED_MAX_HOOK_RETS
  then
    --[[
      try to avoid returning `unpack()` directly,
      because it is a tail call
      that is not fully supported by the JIT compiler.
      So it is better to return the values directly to avoid
      NYI.
    --]]
    local r0, r1, r2, r3 = unpack(acc, 1, acc.n)
    return r0, r1, r2, r3
  end

  return unpack(acc, 1, acc.n)
end


function _M.clear_hooks()
  hooks = {}
end


return _M
