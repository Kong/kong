local re_match = ngx.re.match

local check_regex = function(value)
  if value then
    for _, rule in ipairs(value) do
      local _, err = re_match("just a string to test", rule)
      if err then
        return false, "value '" .. rule .. "' is not a valid regex"
      end
    end
  end
  return true
end

return {
  no_consumer = true,
  fields = {
    whitelist = {
      type = "array",
      func = check_regex,
      new_type = {
        type = "array",
        elements = {
          type = "string",
          match = ".*",
          is_regex = true,
        },
        default = {},
      }
    },
    blacklist = {
      type = "array",
      func = check_regex,
      new_type = {
        type = "array",
        elements = {
          type = "string",
          is_regex = true,
        },
        default = {},
      }
    },
  }
}
