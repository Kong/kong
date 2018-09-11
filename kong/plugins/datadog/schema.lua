local find     = string.find
local pl_utils = require "pl.utils"

local metrics = {
  ["request_count"]         = true,
  ["latency"]               = true,
  ["request_size"]          = true,
  ["status_count"]          = true,
  ["response_size"]         = true,
  ["unique_users"]          = true,
  ["request_per_user"]      = true,
  ["upstream_latency"]      = true,
  ["kong_latency"]          = true,
  ["status_count_per_user"] = true,
}

local stat_types = {
  ["gauge"]     = true,
  ["timer"]     = true,
  ["counter"]   = true,
  ["histogram"] = true,
  ["meter"]     = true,
  ["set"]       = true,
}

local consumer_identifiers = {
  ["consumer_id"] = true,
  ["custom_id"]   = true,
  ["username"]    = true,
}

local default_metrics = {
  {
    name        = "request_count",
    stat_type   = "counter",
    sample_rate = 1,
    tags        = {"app:kong"}
  },
  {
    name      = "latency",
    stat_type = "timer",
    tags      = {"app:kong"}
  },
  {
    name      = "request_size",
    stat_type = "timer",
    tags      = {"app:kong"}
  },
  {
    name        = "status_count",
    stat_type   = "counter",
    sample_rate = 1,
    tags        = {"app:kong"}
  },
  {
    name      = "response_size",
    stat_type = "timer",
    tags      = {"app:kong"}
  },
  {
    name                = "unique_users",
    stat_type           = "set",
    consumer_identifier = "custom_id",
    tags                = {"app:kong"}
  },
  {
    name                = "request_per_user",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = "custom_id",
    tags                = {"app:kong"}
  },
  {
    name      = "upstream_latency",
    stat_type = "timer",
    tags      = {"app:kong"}
  },
  {
    name      = "kong_latency",
    stat_type = "timer",
    tags      = {"app:kong"}
  },
  {
    name                = "status_count_per_user",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = "custom_id",
    tags                = {"app:kong"}
  }
}


-- entries must have colons to set the key and value apart
local function check_tag_value(value)
  if value == nil then
    return true
  end

  for _, entry in ipairs(value) do
    local ok = find(entry, ":")
    if ok then
      local _, next = pl_utils.splitv(entry, ':')
      if not next or #next == 0 then
        return nil, "key '" .. entry .. "' has no value"
      end
    end
  end

  return true
end

local function check_schema(value)
  for _, entry in ipairs(value) do

    if not entry.name  or not entry.stat_type then
      return false, "name and stat_type must be defined for all stats"
    end

    if not metrics[entry.name] then
      return false, "unrecognized metric name: " .. entry.name
    end

    if not stat_types[entry.stat_type] then
      return false, "unrecognized stat_type: " .. entry.stat_type
    end

    local tag_ok, tag_error = check_tag_value(entry.tags)
    if not tag_ok then
      return false, "malformed tags: " .. tag_error
             ..  ". Tags must be list of key[:value]"
    end

    if entry.name == "unique_users" and entry.stat_type ~= "set" then
      return false, "unique_users metric only works with stat_type 'set'"
    end

    if (entry.stat_type == "counter" or entry.stat_type == "gauge")
        and ((not entry.sample_rate) or (entry.sample_rate
        and type(entry.sample_rate) ~= "number")
        or (entry.sample_rate and entry.sample_rate < 1)) then

      return false, "sample rate must be defined for counters and gauges."
    end

    if (entry.name == "status_count_per_user"
        or entry.name == "request_per_user" or entry.name == "unique_users")
        and not entry.consumer_identifier then

      return false, "consumer_identifier must be defined for metric " ..
             entry.name
    end

    if (entry.name == "status_count_per_user"
       or entry.name == "request_per_user"
       or entry.name == "unique_users")
       and entry.consumer_identifier then

      if not consumer_identifiers[entry.consumer_identifier] then

        return false, "invalid consumer_identifier for metric '" ..
               entry.name ..
               "'. Choices are consumer_id, custom_id, and username"
      end
    end

    if (entry.name == "status_count"
       or entry.name == "status_count_per_user"
       or entry.name == "request_per_user")
       and entry.stat_type ~= "counter" then

      return false, entry.name .. " metric only works with stat_type 'counter'"
    end
  end

  return true
end


return {
  fields = {
    host = {
      required = true,
      type     = "string",
      default  = "localhost",
    },
    port = {
      required = true,
      type     = "number",
      default  = 8125,
    },
    metrics = {
      required = true,
      type     = "array",
      default  = default_metrics,
      func     = check_schema,
      new_type = {
        type = "array",
        default  = default_metrics,
        elements = {
          type = "record",
          fields = {
            { name = { type = "string", required = true } },
            { stat_type = { type = "string", required = true } },
            { tags = { type = "array", elements = { type = "string", match = "^.*[^:]$" } } },
            { sample_rate = { type = "number" } },
            { consumer_identifier = { type = "string" } },
          }
        }
      }
    },
    prefix = {
      type     = "string",
      default  = "kong",
    },
  }
}
