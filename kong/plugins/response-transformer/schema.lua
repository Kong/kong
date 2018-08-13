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
      new_type = {
        type = "record",
        fields = {
          { json = { type = "array", elements = { type = "string" }, default = {} } },
          { headers = { type = "array", elements = { type = "string" }, default = {} } },
        },
        nullable = false,
      },
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}}, -- does not need colons
          headers = {type = "array", default = {}} -- does not need colons
        }
      }
    },
    replace = {
      new_type = {
        type = "record",
        fields = {
          { json = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { headers = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
        },
        nullable = false,
      },
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value}
        }
      }
    },
    add = {
      new_type = {
        type = "record",
        fields = {
          { json = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { headers = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
        },
        nullable = false,
      },
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value}
        }
      }
    },
    append = {
      new_type = {
        type = "record",
        fields = {
          { json = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { headers = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
        },
        nullable = false,
      },
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
