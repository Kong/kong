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

local function check_method(value)
  if not value then
    return true
  end
  local method = value:upper()
  local ngx_method = ngx["HTTP_" .. method]
  if not ngx_method then
    return false, method .. " is not supported"
  end
  return true
end

return {
  fields = {
    http_method = {type = "string", func = check_method},
    remove = {
      new_type = {
        type = "record",
        fields = {
          { body = { type = "array", elements = { type = "string" }, default = {} } },
          { headers = { type = "array", elements = { type = "string" }, default = {} } },
          { querystring = { type = "array", elements = { type = "string" }, default = {} } },
        },
        nullable = false,
      },
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
      new_type = {
        type = "record",
        fields = {
          { body = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { headers = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { querystring = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
        },
        nullable = false,
      },
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
      new_type = {
        type = "record",
        fields = {
          { body = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { headers = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { querystring = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
        },
        nullable = false,
      },
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
      new_type = {
        type = "record",
        fields = {
          { body = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { headers = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { querystring = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
        },
        nullable = false,
      },
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
      new_type = {
        type = "record",
        fields = {
          { body = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { headers = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
          { querystring = { type = "array", elements = { type = "string", match = "^[^:]+:.*$" }, default = {} } },
        },
        nullable = false,
      },
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
