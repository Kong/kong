-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
