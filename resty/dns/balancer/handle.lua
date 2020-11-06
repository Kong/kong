---
-- Handle module.
--
-- Implements handles to be used by the `objBalancer:getPeer` method. These
-- implement a __gc method for tracking statistics and not leaking resources
-- in case a connection gets aborted prematurely.
--
-- This module is only relevant when implementing your own balancer
-- algorithms.
--
-- @author Thijs Schreijer
-- @copyright 2016-2020 Kong Inc. All rights reserved.
-- @license Apache 2.0


local table_new = require "table.new"
local table_clear = require "table.clear"
local EMPTY = setmetatable({},
  {__newindex = function() error("The 'EMPTY' table is read-only") end})


local cache_max = 1000
local cache_count = 0
local cache = table_new(cache_max, 0)


local _M = {}


local createHandle
do
  local function udata_gc_method(self)
    -- find our handle
    local mt = getmetatable(self)
    local handle = mt.handle
    -- disconnect handle and udata
    mt.handle = nil
    handle.__udata = nil
    -- find __gc method
    local __gc = (handle or EMPTY).__gc
    if not __gc then
      return
    end
    -- execute __gc method
    __gc(handle)
  end

  function createHandle(__gc)
    -- create handle
    local handle = {
      __gc = __gc
    }
    -- create userdata
    local __udata = newproxy(true)
    local mt = getmetatable(__udata)
    mt.__gc = udata_gc_method
    -- connect handle and userdata
    mt.handle = handle
    handle.__udata = __udata

    return handle
  end
end

--- Gets a handle from the cache.
-- The handle comes from the cache or it is newly created. A handle is just a
-- table. It will have two special fields:
--
-- - `__udata`: (read-only) a userdata used to track the lifetime of the handle
-- - `__gc`: (read/write) this method will be called on GC.
--
-- __NOTE__: the `__gc` will only be called when the handle is garbage collected,
-- not when it is returned by calling `release`.
-- @param __gc (optional, function) the method called when the handle is GC'ed.
-- @return handle
-- @usage
-- local handle = _M
--
-- local my_gc_handler = function(self)
--   print(self.name .. " was deleted")
-- end
--
-- local h1 = handle.get(my_gc_handler)
-- h1.name = "Obama"
-- local h2 = handle.get(my_gc_handler)
-- h2.name = "Trump"
--
-- handle.release(h1)   -- explicitly release it
-- h1 = nil
-- h2 = nil             -- not released, will be GC'ed
-- collectgarbage()
-- collectgarbage()     --> "Trump was deleted"
function _M.get(__gc)
  if cache_count == 0 then
    -- cache is empty, create a new one
    return createHandle(__gc)
  end
  local handle = cache[cache_count]
  cache[cache_count] = nil
  cache_count = cache_count - 1
  handle.__gc = __gc
  return handle
end

--- Returns a handle to the cache.
-- The handle will be cleared, returned to the cache, and its `__gc` handle
-- will NOT be called.
-- @param handle the handle to return to the cache
-- @return nothing
function _M.release(handle)
  local __udata = handle.__udata
  if not __udata then
    -- this one was GC'ed, we check this because we do not want
    -- to accidentally ressurect a handle.
    return
  end
  if cache_count >= cache_max then
    -- we're dropping this one, our cache is full
    handle.__udata = nil
    handle.__gc = nil
    return
  end
  -- return it to the cache
  table_clear(handle)
  handle.__udata = __udata
  cache_count = cache_count + 1
  cache[cache_count] = handle
end


--- Sets a new cache size. The default size is 1000.
-- @param size the new size.
-- @return nothing, or throws an error on bad input
function _M.setCacheSize(size)
  assert(type(size) == "number", "expected a number")
  assert(size >= 0, "expected size >= 0")
  cache_max = size
  local new_cache = table_new(cache_max, 0)
  cache_count = math.min(cache_count, size)
  for i = 1, cache_count do
    new_cache[i] = cache[i]
  end
  cache = new_cache
end


return _M
