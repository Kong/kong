local new_tab
local clear_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function (narr, nrec) return {} end
  end

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
