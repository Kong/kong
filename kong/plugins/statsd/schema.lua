local metrics = {
  "request_count",
  "latency",
  "request_size",
  "status_count",
  "response_size",
  "unique_users",
  "request_per_user",
  "upstream_latency",
  "kong_latency",
  "status_count_per_user"
}

local stat_types = {
  "gauge",
  "timer",
  "counter",
  "histogram",
  "meter",
  "set"
}

local consumer_identifiers = {
  "consumer_id",
  "custom_id",
  "username"
}

local default_metrics = {
  {
    name = "request_count",
    stat_type = "counter",
    sample_rate = 1
  },
  {
    name = "latency",
    stat_type = "timer"
  },
  {
    name = "request_size",
    stat_type = "timer"
  },
  {
    name = "status_count",
    stat_type = "counter",
    sample_rate = 1
  },
  {
    name = "response_size",
    stat_type = "timer"
  },
  {
    name = "unique_users",
    stat_type = "set",
    consumer_identifier = "custom_id"
  },
  {
    name = "request_per_user",
    stat_type = "counter",
    sample_rate = 1,
    consumer_identifier = "custom_id"
  },
  {
    name = "upstream_latency",
    stat_type = "timer"
  },
  {
    name = "kong_latency",
    stat_type = "timer"
  },
  {
    name = "status_count_per_user",
    stat_type = "counter",
    sample_rate = 1,
    consumer_identifier = "custom_id"
  }
}

local function check_value(table, element)
  for _, value in pairs(table) do
    if value == element then
      return true
    end
  end
  return false
end

local function check_schema(value)
  for _, entry in ipairs(value) do
    local name_ok = check_value(metrics, entry.name)
    local type_ok = check_value(stat_types, entry.stat_type)
    
    if entry.name == nil or entry.stat_type == nil then
      return false, "name and stat_type must be defined for all stats"
    end
    if not name_ok then
      return false, "unrecognized metric name: "..entry.name
    end
    if not type_ok then
      return false, "unrecognized stat_type: "..entry.stat_type
    end
    if entry.name == "unique_users" and entry.stat_type ~= "set" then
      return false, "unique_users metric only works with stat_type 'set'"
    end
    if (entry.stat_type == "counter" or entry.stat_type == "gauge") and ((entry.sample_rate == nil) or (entry.sample_rate ~= nil and type(entry.sample_rate) ~= "number") or (entry.sample_rate ~= nil and entry.sample_rate < 1)) then
      return false, "sample rate must be defined for counters and gauges."
    end
    if (entry.name == "status_count_per_user" or entry.name == "request_per_user" or entry.name == "unique_users") and entry.consumer_identifier == nil then
      return false, "consumer_identifier must be defined for metric "..entry.name
    end
    if (entry.name == "status_count_per_user" or entry.name == "request_per_user" or entry.name == "unique_users") and entry.consumer_identifier ~= nil then
      local identifier_ok = check_value(consumer_identifiers, entry.consumer_identifier)
      if not identifier_ok then
        return false, "invalid consumer_identifier for metric "..entry.name..". Choices are consumer_id, custom_id, and username"
      end
    end
    if (entry.name == "status_count" or entry.name == "status_count_per_user" or entry.name == "request_per_user") and entry.stat_type ~= "counter" then
      return false, entry.name.." metric only works with stat_type 'counter'"
    end
  end
  return true
end

return {
  fields = {
    host = {required = true, type = "string", default = "localhost"},
    port = {required = true, type = "number", default = 8125},
    metrics = {
      type = "array",
      required = true,
      default = default_metrics,
      func = check_schema
    },
    timeout = {type = "number", default = 10000}
  }
}
