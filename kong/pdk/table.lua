--- Utilities for Lua tables
--
-- @module kong.table

local rawset = rawset
local setmetatable = setmetatable
local assert = assert

local new_tab
local clear_tab
do
  ---
  -- Returns a table with pre-allocated number of slots in its array and hash
  -- parts.
  --
  -- @function kong.table.new
  -- @tparam[opt] number narr specifies the number of slots to pre-allocate
  -- in the array part.
  -- @tparam[opt] number nrec specifies the number of slots to pre-allocate in
  -- the hash part.
  -- @treturn table the newly created table
  -- @usage
  -- local tab = kong.table.new(4, 4)
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function (narr, nrec) return {} end
  end


  ---
  -- Clears a table from all of its array and hash parts entries.
  --
  -- @function kong.table.clear
  -- @tparam table tab the table which will be cleared
  -- @return Nothing
  -- @usage
  -- local tab = {
  --   "hello",
  --   foo = "bar"
  -- }
  --
  -- kong.table.clear(tab)
  --
  -- kong.log(tab[1]) -- nil
  -- kong.log(tab.foo) -- nil
  ok, clear_tab = pcall(require, "table.clear")
  if not ok then
    clear_tab = function (tab)
      for k, _ in pairs(tab) do
        tab[k] = nil
      end
    end
  end
end


--- Merges the contents of two tables together, producing a new one.
-- The entries of both tables are copied non-recursively to the new one.
-- If both tables have the same key, the second one takes precedence.
-- @function kong.table.merge
-- @tparam table t1 The first table
-- @tparam table t2 The second table
-- @treturn table The (new) merged table
-- @usage
-- local t1 = {1, 2, 3, foo = "f"}
-- local t2 = {4, 5, bar = "b"}
-- local t3 = kong.table.merge(t1, t2) -- {4, 5, 3, foo = "f", bar = "b"}
local function merge_tab(t1, t2)
  local res = {}
  if t1 then
    for k,v in pairs(t1) do
      res[k] = v
    end
  end
  if t2 then
    for k,v in pairs(t2) do
      res[k] = v
    end
  end
  return res
end


--- Creates a new cache table (or memoize).
-- A Cache table is typically used to convert configuration values once at
-- load-time. To avoid expensive operations at run-time. The cache will
-- have weak-keys, so the lifetime of the values is bound to the lifetime
-- of the keys.
--
-- Whenever a key is not found on lookup, the `convert_func` will be invoked to
-- generate the value.
--
-- @function kong.table.merge
-- @tparam function convert_func the conversion function
-- @treturn table The cache table
-- @usage
-- local config_cache = kong.table.new_cache(function(conf)
--   -- assume we have a config table that has an array with strings
--   -- but at runtime we'd like a reverse lookup table instead of iterating
--   -- over the table on every request
--   local hash = {}
--   for i, v in ipairs(conf.array) do
--     hash[value] = i
--   end
--   return {
--     hash = hash,
--     array = conf.array,
--   }
-- end)
--
-- function my_plugin.access(conf)
--   conf = config_cache[conf]  -- generates it if not found
--
--   local value = ngx.req.get_headers()["My-Header"]
--   if conf.hash[value] then  -- reverse-lookup instead of array traversal
--     ngx.log(ngx.WARN, "the configured value was actually found")
--   end
-- end
local function new_cache(convert_func)
  return setmetatable({}, {
    __mode = "k",
    __index = function(self, key)
      if type(key) ~= "table" then
        error(("the key must be a table, got '%s'"):format(type(key)), 2)
      end

      local value = assert(convert_func(key))
      assert(value ~= key, "the value cannot be the same table") -- memory leak

      rawset(self, key, value)
      return value
    end,
  })
end


local function new(self)
  return {
    new = new_tab,
    clear = clear_tab,
    merge = merge_tab,
    new_cache = new_cache,
  }
end


return {
  new = new,
}
