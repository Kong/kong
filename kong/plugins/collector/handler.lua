-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local BatchQueue = require "kong.tools.batch_queue"
local cjson_safe = require "cjson.safe"
local http = require "resty.http"

local date = require "date"

local queue

local CollectorHandler = {
  PRIORITY = 903,
  VERSION = "2.1.2"
}

local messaging = require "kong.tools.messaging"

local TELEMETRY_VERSION = "v1"
local TELEMETRY_TYPE = "collector"

local SHM_KEY = "collector-har-buffering"
local SHM = ngx.shared.kong

local COLLECTOR_TYPE_STATS = 0x3

-- Sends the provided payload (a string) to the configured plugin host
-- @return true if everything was sent correctly, falsy if error
-- @return error message if there was an error
local function send_payload(http_endpoint, payload)
  local client = http.new()

  local headers = { ["Content-Type"] = "application/json", ["Content-Length"] = #payload }
  local params = { method = "POST", body = payload, headers = headers }
  local trimmed_endpoint = http_endpoint:gsub("(.-)/$", "%1")
  local res, err = client:request_uri(trimmed_endpoint .. '/hars' , params)

  if not res then
    return nil, "failed request to " .. http_endpoint .. ": " .. err
  end

  if res.status < 400 then
    return false, "request to " .. http_endpoint .. " returned " .. tostring(res.status)
  end

  return true
end

local function json_array_concat(entries)
  local serialized_entries = {}
  for i, entry in ipairs(entries) do
    serialized_entries[i] = cjson_safe.encode(entry)
  end
  return "[" .. table.concat(serialized_entries, ",") .. "]"
end

local function update_ticket_to_ride(premature, self)
  local now = ngx.now()
  local license_data = (kong.license and kong.license.license) and kong.license.license.payload or nil

  if license_data then
    local delta = date.diff(license_data.license_expiration_date, now)
    if delta:spandays() >= -30 then  -- 30 days of grace period
      self.valid_license = true
    else
      self.valid_license = false
    end
  else
    self.valid_license = false
  end

  ngx.timer.at(60, update_ticket_to_ride, self)
end

local function obfuscate_query_parameters(entry)
  for key, value in pairs(entry['request']['querystring']) do
    if tonumber(value) == nil then
      entry['request']['querystring'][key] = string.rep('x', #value)
    else
      entry['request']['querystring'][key] = string.rep('0', #value)
    end
  end

  return entry
end

local function create_queue(conf, self)
  -- batch_max_size <==> conf.queue_size
  local batch_max_size = conf.queue_size or 1
  local process = function(entries)
    local payload

    if #entries == 1 or batch_max_size == 1 then
      payload = cjson_safe.encode(entries[1])
    else
      payload = json_array_concat(entries)
    end

    if not self.hybrid then
      return send_payload(conf.http_endpoint, payload)
    else
      local data = {
        http_endpoint = conf.http_endpoint,
        payload = payload
      }
      return self.messaging:send_message(COLLECTOR_TYPE_STATS, cjson_safe.encode(data), true)
    end
  end

  local opts = {
    retry_count = conf.retry_count,
    flush_timeout = 1,
    batch_max_size = batch_max_size,
    process_delay = 0,
  }

  local q, err = BatchQueue.new(process, opts)
  if not q then
    kong.log.err("could not create queue: ", err)
    return
  end
  queue = q
end

local function get_serve_ingest_func(self)
  return function(data)
    if data[2] then
      local payload = cjson_safe.decode(data[2])
      send_payload(payload["http_endpoint"], payload["payload"])
    end
  end
end


local function make_message_pipe(self)
  local hybrid_cp = kong.configuration.role == "control_plane"
  -- Make the messaging pipe object
  return messaging.new({
    type = hybrid_cp and messaging.TYPE.CONSUMER or messaging.TYPE.PRODUCER,
    cluster_endpoint = kong.configuration.cluster_telemetry_endpoint,
    message_type = TELEMETRY_TYPE,
    message_type_version = TELEMETRY_VERSION,
    serve_ingest_func = get_serve_ingest_func(self),
    shm = SHM,
    shm_key = SHM_KEY,
  })
end

local function get_server_name()
  local conf = kong.configuration
  local server_name
  if conf.cluster_mtls == "shared" then
    server_name = "kong_clustering"
  else
    -- server_name will be set to the host if it is not explicitly defined here
    if conf.cluster_telemetry_server_name ~= "" then
      server_name = conf.cluster_telemetry_server_name
    elseif conf.cluster_server_name ~= "" then
      server_name = conf.cluster_server_name
    end
  end
  return server_name
end

function CollectorHandler:init_worker()
  if string.match(kong.version, "enterprise") then
    self.kong_ee = true
  else
    self.kong_ee = false
  end

  self.hybrid = kong.configuration.role ~= "traditional"
  self.role = kong.configuration.role
  self.valid_license = false
  update_ticket_to_ride(false, self)

  -- start messanging pipe/register pipe
  if self.hybrid then
    local err
    self.messaging, err = make_message_pipe(self)
    if not self.messaging then
      kong.log.err("Could not start pipe between DP and CP for Collector Plugin: " .. err)
    end

    if self.role == "data_plane" then
      return self.messaging:start_client(get_server_name())
    else
      self.messaging:register_for_messages()
    end
  end
end

function CollectorHandler:log(conf)
  if not self.kong_ee or not self.valid_license or (self.hybrid and self.role ~= "data_plane") then
    return
  end

  local entry = kong.log.serialize()
  entry["request"]["post_data"] = {}

  if not queue then
    create_queue(conf, self)
  end

  if entry then
    queue:add(obfuscate_query_parameters(entry))
  end

end

return CollectorHandler
