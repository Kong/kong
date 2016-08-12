local find = string.find
-- entries must have colons to set the key and value apart
local function check_for_value(value)
  for i, entry in ipairs(value) do
    local ok = find(entry, ":")
    if not ok then
      return false, "key '"..entry.."' has no value"
    end
  end
  return true
end

return {
  fields = {
    rename = {
      type = "table",
      schema = {
        fields = {
          body = {type = "array", default = {}},
          headers = {type = "array", default = {}},
          querystring = {type = "array", default = {}} 
        }
      }
    },
    remove = {
      type = "table",
      schema = {
        fields = {
          body = {type = "array", default = {}}, -- does not need colons
          headers = {type = "array", default = {}}, -- does not need colons
          querystring = {type = "array", default = {}} -- does not need colons
        }
      }
    },
    rename = {
      type = "table",
      schema = {
        fields = {
          body = {type = "array", default = {}},
          headers = {type = "array", default = {}},
          querystring = {type = "array", default = {}}
        }
      }
    },
    replace = {
      type = "table",
      schema = {
        fields = {
          body = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value},
          querystring = {type = "array", default = {}, func = check_for_value}
        }
      }
    },
    add = {
      type = "table",
      schema = {
        fields = {
          body = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value},
          querystring = {type = "array", default = {}, func = check_for_value}
        }
      }
    },
    append = {
      type = "table",
      schema = {
        fields = {
          body = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value},
          querystring = {type = "array", default = {}, func = check_for_value}
        }
      }
    }
  }
}
