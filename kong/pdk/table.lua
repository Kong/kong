--- Utilities for Lua tables
--
-- @module kong.table


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


local function new(self)
  return {
    new = new_tab,
    clear = clear_tab,
    merge = merge_tab,
  }
end


return {
  new = new,
}
