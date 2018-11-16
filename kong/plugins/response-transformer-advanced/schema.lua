local find = string.find
-- entries must have colons to set the key and value apart
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
  fields = {
    -- add: Add a value (to response headers or response JSON body) only if the key does not already exist.
    remove = {
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}}, -- does not need colons
          headers = {type = "array", default = {}} -- does not need colons
        }
      }
    },
    replace = {
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value}
        }
      }
    },
    add = {
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value}
        }
      }
    },
    append = {
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value}
        }
      }
    }
  }
}
