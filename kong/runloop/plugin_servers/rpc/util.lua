local function index_table(table, field)
    if table[field] then
      return table[field]
    end

    local res = table
    for segment, e in ngx.re.gmatch(field, "\\w+", "jo") do
      if res[segment[0]] then
        res = res[segment[0]]
      else
        return nil
      end
    end
    return res
  end

return {
    index_table = index_table,
}
