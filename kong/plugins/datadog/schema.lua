local find = string.find
local pl_utils = require "pl.utils"
local metrics = {
  "request_count",
  "latency",
  "request_size",
  "status_count",
  "response_size",
  "unique_users",
  "request_per_user",
  "upstream_latency"
}
-- entries must have colons to set the key and value apart
local function check_for_value(value)
  for i, entry in ipairs(value) do
    local ok = find(entry, ":")
    if ok then 
      local _,next = pl_utils.splitv(entry, ':')
      if not next or #next == 0 then
        return false, "key '"..entry.."' has no value, "
      end
    end
  end
  return true
end
return {
  fields = {
    host = {required = true, type = "string", default = "localhost"},
    port = {required = true, type = "number", default = 8125},
    metrics = {required = true, type = "array", enum = metrics, default = metrics},
    tags = {
      type = "table",
      schema = {
        fields = {
          request_count = {type = "array", default = {}, func = check_for_value},
          latency = {type = "array", default = {}, func = check_for_value},
          request_size = {type = "array", default = {}, func = check_for_value},
          status_count = {type = "array", default = {}, func = check_for_value},
          response_size = {type = "array", default = {}, func = check_for_value},
          unique_users = {type = "array", default = {}, func = check_for_value},
          request_per_user = {type = "array", default = {}, func = check_for_value},
          upstream_latency = {type = "array", default = {}, func = check_for_value}
        }
      }
    },
    timeout = {type = "number", default = 10000}
  }
}
