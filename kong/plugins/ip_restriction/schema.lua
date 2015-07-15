local function validate_ips(v, t, column)
  local iputils = require "resty.iputils"
  local new_fields
  if v and type(v) == "table" then
    for _, ip in ipairs(v) do
      local _, err = iputils.parse_cidr(ip)
      if type(err) == "string" then -- It's an error only if the second variable is a string
        return false, err
      end
    end
    new_fields = { ["_"..column.."_cache"] = iputils.parse_cidrs(v) }
  end
  return true, nil, new_fields
end

return {
  fields = {
    whitelist = { type = "array", func = validate_ips },
    blacklist = { type = "array", func = validate_ips },

    -- Internal use
    _whitelist_cache = { type = "array" },
    _blacklist_cache = { type = "array" }
  }
}
