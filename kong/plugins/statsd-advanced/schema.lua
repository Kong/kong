-- add vitals metrics
local vitals = require "kong.vitals"
local constants = require "kong.plugins.statsd-advanced.constants"


local match = ngx.re.match
local ee_metrics = vitals.logging_metrics or {}


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
  -- EE only
  ["status_count_per_workspace"]      = true,
  ["status_count_per_user_per_route"] = true,
  ["shdict_usage"]                    = true,
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

local service_identifiers = {
  ["service_id"]           = true,
  ["service_name"]         = true,
  ["service_host"]         = true,
  ["service_name_or_host"] = true,
}

local workspace_identifiers = {
  ["workspace_id"]         = true,
  ["workspace_name"]       = true,
}

local default_metrics = {
  {
    name               = "request_count",
    stat_type          = "counter",
    sample_rate        = 1,
    service_identifier = "service_name_or_host"
  },
  {
    name               = "latency",
    stat_type          = "timer",
    service_identifier = "service_name_or_host",
  },
  {
    name               = "request_size",
    stat_type          = "timer",
    service_identifier = "service_name_or_host",
  },
  {
    name               = "status_count",
    stat_type          = "counter",
    sample_rate        = 1,
    service_identifier = "service_name_or_host",
  },
  {
    name               = "response_size",
    stat_type          = "timer",
    service_identifier = "service_name_or_host",
  },
  {
    name                = "unique_users",
    stat_type           = "set",
    consumer_identifier = "custom_id",
    service_identifier  = "service_name_or_host",
  },
  {
    name                = "request_per_user",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = "custom_id",
    service_identifier  = "service_name_or_host",
  },
  {
    name               = "upstream_latency",
    stat_type          = "timer",
    service_identifier = "service_name_or_host",
  },
  {
    name               = "kong_latency",
    stat_type          = "timer",
    service_identifier = "service_name_or_host",
  },
  {
    name                = "status_count_per_user",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = "custom_id",
    service_identifier  = "service_name_or_host",
  },
  -- EE only
  {
    name                 = "status_count_per_workspace",
    stat_type            = "counter",
    sample_rate          = 1,
    workspace_identifier = "workspace_id",
  },
  {
    name                = "status_count_per_user_per_route",
    stat_type           = "counter",
    sample_rate         = 1,
    consumer_identifier = "custom_id",
    service_identifier  = "service_name_or_host",
  },
  {
    name               = "shdict_usage",
    stat_type          = "gauge",
    sample_rate        = 1,
    service_identifier = "service_name_or_host",
  },
}

for _, group in pairs(ee_metrics) do
  for metric, metric_type in pairs(group) do
    metrics[metric] = "true"
    default_metrics[#default_metrics + 1] = {
      name        = metric,
      stat_type   = metric_type,
      sample_rate = 1
    }
  end
end

local function check_schema(value)
  for _, entry in ipairs(value) do

    if not entry.name or not entry.stat_type then
      return false, "name and stat_type must be defined for all stats"
    end

    if not metrics[entry.name] then
      return false, "unrecognized metric name: " .. entry.name
    end

    if not stat_types[entry.stat_type] then
      return false, "unrecognized stat_type: " .. entry.stat_type
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

    -- allow nil service_identifier for ce schema service_identifier is not defined
    if entry.service_identifier and not service_identifiers[entry.service_identifier] then
      return false, "invalid service_identifier for metric '" ..
               entry.name ..
               "'. Choices are service_id, service_name, service_host and service_name_or_host"
    end

    if (entry.name == "status_count_per_user"
        or entry.name == "status_count_per_user_per_route"
        or entry.name == "request_per_user" or entry.name == "unique_users")
        and not entry.consumer_identifier then

      return false, "consumer_identifier must be defined for metric " ..
             entry.name
    end

    if (entry.name == "status_count_per_user"
       or entry.name == "status_count_per_user_per_route"
       or entry.name == "request_per_user"
       or entry.name == "unique_users")
       and entry.consumer_identifier
       and not consumer_identifiers[entry.consumer_identifier] then

        return false, "invalid consumer_identifier for metric '" ..
               entry.name ..
               "'. Choices are consumer_id, custom_id, and username"
    end

    if entry.name == "status_count_per_workspace"
        and not entry.workspace_identifier then

      return false, "workspace_identifier must be defined for metric " ..
             entry.name
    end

    if entry.name == "status_count_per_workspace"
        and entry.workspace_identifier
        and not workspace_identifiers[entry.workspace_identifier] then

     return false, "invalid workspace_identifier for metric '" ..
            entry.name ..
            "'. Choices are workspace_id and workspace_name"
    end

    if (entry.name == "status_count"
       or entry.name == "status_count_per_user"
       or entry.name == "status_count_per_workspace"
       or entry.name == "status_count_per_user_per_route"
       or entry.name == "request_per_user")
       and entry.stat_type ~= "counter" then

      return false, entry.name .. " metric only works with stat_type 'counter'"
    end

    if entry.name == "shdict_usage" and entry.stat_type ~= "gauge" then

      return false, entry.name .. " metric only works with stat_type 'gauge'"
    end

    -- check vitals metrics
    for _, group in pairs(ee_metrics) do
      for metric, metric_type in pairs(group) do
        if metric == entry.name and metric_type ~= entry.stat_type then
          return false, entry.name .. " metric only works with stat_type '" .. metric_type .."'"
        end
      end
    end

  end

  return true
end

local function check_allow_status_codes(value)
  if not value then
    return true
  end

  for _, range in pairs(value) do
    -- Get status code range splitting by "-" character
    local range = match(range, constants.REGEX_STATUS_CODE_RANGE, "oj")

    -- Checks if there are both interval numbers
    if not range then
      return false, "ranges should be provided in a format number-number and separated by commas"
    end
  end
  return true;
end

local function check_udp_packet_size(value)
  if value < 0 then
    return false, "udp_packet_size can't be smaller than 0"
  elseif value > 65507 then
    -- 65,507 bytes (65,535 − 8 byte UDP header − 20 byte IP header) -- Wikipedia
    return false, "udp_packet_size can't be larger than 65507"
  end
  return true
end


return {
  fields = {
    host    = {
      type     = "string",
      default  = "localhost",
    },
    port    = {
      type     = "number",
      default  = 8125,
    },
    metrics = {
      type     = "array",
      default  = default_metrics,
      func     = check_schema,
    },
    prefix =
    {
      type     = "string",
      default  = "kong",
    },
    allow_status_codes = {
      type    = "array",
      func     = check_allow_status_codes,
    },
    -- EE only
    udp_packet_size = {
      type     = "number",
      default  = 0, -- combine udp packet up to this value, don't combine if it's 0
      func     = check_udp_packet_size,
    },
    use_tcp = {
      type     = "boolean",
      default  = false,
    },
    hostname_in_prefix = {
      type    = "boolean",
      default = false,
    }
  },
}
