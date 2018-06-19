--- Utilities for Lua tables
-- @module kong.table
local new_tab
local clear_tab
do
  ---
  -- Returns a table with pre-allocated number of slots in its array and hash parts.
  -- @function kong.table.new
  -- @tparam[opt] number narr specifies the number of slots to pre-allocate in the
  -- @tparam[opt] number nrec specifies the number of slots to pre-allocate in the hash part.
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


local function new(self)
  return {
    new = new_tab,
    clear = clear_tab,
  }
end


return {
  new = new,
}
