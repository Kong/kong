-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local BasePlugin = require "kong.plugins.base_plugin"
local BatchQueue = require "kong.tools.batch_queue"
local cjson_safe = require "cjson.safe"
local http = require "resty.http"

local allowed_to_run = true
local queue

local CollectorHandler = BasePlugin:extend()

local messaging = require "kong.tools.messaging"
local TELEMETRY_VERSION = "v1"
local TELEMETRY_TYPE = "collector"
local SHM = ngx.shared.kong
local SHM_KEY = "collector-request-har"

local COLLECTOR_TYPE_STATS = 0x1


CollectorHandler.PRIORITY = 903
CollectorHandler.VERSION = "2.0.4"

-- Sends the provided payload (a string) to the configured plugin host
-- @return true if everything was sent correctly, falsy if error
-- @return error message if there was an error
local function send_payload(data_encoded)
  local data = cjson_safe.decode(data_encoded)
  local client = http.new()

  local headers = { ["Content-Type"] = "application/json", ["Content-Length"] = #data.payload }

  local params = { method = "POST", body = data.payload, headers = headers }

  local trimmed_endpoint = data.http_endpoint:gsub("(.-)/$", "%1")
  local res, err = client:request_uri(trimmed_endpoint .. '/hars' , params)

  if not res then
    return nil, "failed request to " .. data.http_endpoint .. ": " .. err
  end

  local success = res.status < 400
  local err_msg

  if not success then
    err_msg = "request to " .. data.http_endpoint .. " returned " .. tostring(res.status)
  end

  return success, err_msg
end

local function json_array_concat(entries)
  return "[" .. table.concat(entries, ",") .. "]"
end


local function create_queue(conf, self)
  -- batch_max_size <==> conf.queue_size
  local batch_max_size = conf.queue_size or 1
  local process = function(entries)
    local payload

    if #entries == 1 or batch_max_size == 1 then
      payload = entries[1]
    else
      payload = json_array_concat(entries)
    end

    local data = {
      http_endpoint = conf.http_endpoint,
      payload = payload
    }

    if not self.hybrid then
      return send_payload(cjson_safe.encode(data))
    else
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
  return function(payload)
    send_payload(payload[2])
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

function CollectorHandler:new()
  if string.match(kong.version, "enterprise") then
    allowed_to_run = true
    self.hybrid = kong.configuration.role ~= "traditional"
    self.role = kong.configuration.role

    if self.hybrid then
      self.messaging, err = make_message_pipe(self)
      if not self.messaging then
        kong.log.err("Could not start pipe between DP and CP for Collector Plugin")
      end
    end
  else
    allowed_to_run = false
  end
end


function CollectorHandler:init(...)
end

function CollectorHandler:init_worker(conf)
  if not allowed_to_run then
    return
  end
  -- start messanging pipe/register pipe
  if self.hybrid then
    if self.role == "data_plane" then
      return self.messaging:start_client(get_server_name())
    else
      self.messaging:register_for_messages()
    end
  end
end


function CollectorHandler:log(conf)
  if not allowed_to_run or (self.hybrid and self.role ~= "data_plane") then
    return
  end

  local entry = kong.log.serialize()
  entry["request"]["post_data"] = {}
  entry = cjson_safe.encode(entry)

  if not queue then
    create_queue(conf, self)
  end

  if entry then
    queue:add(entry)
  end

end

return CollectorHandler


