-- to avoid unnecessary table creation
local function inplace_merge(lst, lst2)
  if lst == nil then
    return lst2, #lst2
  end


  local n = #lst
  local m = #lst2
  for i = 1, m do
    n = n + 1
    lst[n] = lst2[i]
  end

  return lst, n
end

return {
  inplace_merge = inplace_merge,
}