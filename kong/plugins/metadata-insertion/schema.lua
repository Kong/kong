local find = string.find
local function check_for_value(value)
  for i, entry in ipairs(value) do
    local ok = find(entry, ":")
    if not ok then
      return false, "key '" .. entry .. "' has no value"
    end
  end
  return true
end

return {
  no_consumer = true,
  fields = {
    add = {
      type = "table",
      schema = {
        fields = {
          querystring = { type = "array", default = {}, func = check_for_value },
          headers = { type = "array", default = {}, func = check_for_value }
        }
      }
    },
    replace = {
      type = "table",
      schema = {
        fields = {
          querystring = { type = "array", default = {}, func = check_for_value },
          headers = { type = "array", default = {}, func = check_for_value }
        }
      }
    },
    remove = {
      type = "table",
      schema = {
        fields = {
          querystring = { type = "array" },
          headers = { type = "array" }
        }
      }
    }
  }
}
