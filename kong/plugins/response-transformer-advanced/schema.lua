local constants = require "kong.plugins.response-transformer-advanced.constants"

local find = string.find
local match = ngx.re.match


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

-- checks if status code entries follow status code or status code range pattern (xxx or xxx-xxx)
local function check_status_code_format(status_codes)
  for _, entry in pairs(status_codes) do
    local single_code = match(entry, constants.REGEX_SINGLE_STATUS_CODE)
    local range = match(entry, constants.REGEX_SPLIT_RANGE)

    if not single_code and not range then
      return false, "value '" .. entry .. "' is neither status code nor status code range"
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
          headers = {type = "array", default = {}}, -- does not need colons
          if_status = {type = "array", default = {}, func = check_status_code_format},
        }
      }
    },
    replace = {
      type = "table",
      schema = {
        fields = {
          body = {type = "string"},
          json = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value},
          if_status = {type = "array", default = {}, func = check_status_code_format},
        }
      }
    },
    add = {
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value},
          if_status = {type = "array", default = {}, func = check_status_code_format},
        }
      }
    },
    append = {
      type = "table",
      schema = {
        fields = {
          json = {type = "array", default = {}, func = check_for_value},
          headers = {type = "array", default = {}, func = check_for_value},
          if_status = {type = "array", default = {}, func = check_status_code_format},
        }
      }
    }
  }
}
