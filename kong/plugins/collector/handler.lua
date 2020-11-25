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

CollectorHandler.PRIORITY = 903
CollectorHandler.VERSION = "2.0.2"

-- Sends the provided payload (a string) to the configured plugin host
-- @return true if everything was sent correctly, falsy if error
-- @return error message if there was an error
local function send_payload(conf, payload)
  local client = http.new()
  local headers = { ["Content-Type"] = "application/json", ["Content-Length"] = #payload }
  local params = { method = "POST", body = payload, headers = headers }
  local trimmed_endpoint = conf.http_endpoint:gsub("(.-)/$", "%1")
  local res, err = client:request_uri(trimmed_endpoint .. '/hars' , params)

  if not res then
    return nil, "failed request to " .. conf.http_endpoint .. ": " .. err
  end

  local success = res.status < 400
  local err_msg

  if not success then
    err_msg = "request to " .. conf.http_endpoint .. " returned " .. tostring(res.status)
  end

  return success, err_msg
end

local function json_array_concat(entries)
  return "[" .. table.concat(entries, ",") .. "]"
end

local function create_queue(conf)
  -- batch_max_size <==> conf.queue_size
  local batch_max_size = conf.queue_size or 1
  local process = function(entries)
    local payload
    if #entries == 1 or batch_max_size == 1 then
      payload = entries[1]
    else
      payload = json_array_concat(entries)
    end
    return send_payload(conf, payload)
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

local function remove_sensible_data_from_table(conf, a_table, depth)
  local clean = {}
  depth = depth or 1
  local max_depth = conf.body_parsing_max_depth or 1

  if depth == max_depth then
    return { field_type = "dict" }
  end

  if a_table then
    for key, value in pairs(a_table) do
      if type(value) == "table" and #value > 0 then
        clean[key] = { field_type = "array", field_length = #value }
      elseif type(value) == "table" then
        clean[key] = remove_sensible_data_from_table(conf, value, depth + 1)
      elseif type(value) == "string" then
        clean[key] = { field_type = "string", field_length = #value }
      elseif type(value) == "number" then
        clean[key] = { field_type = "number"  }
      end
    end
  end

  return clean
end
CollectorHandler.remove_sensible_data_from_table = remove_sensible_data_from_table

function CollectorHandler:new()
  if string.match(kong.version, "enterprise") then
    allowed_to_run = true
  else
    allowed_to_run = false
  end
end

function CollectorHandler:access(conf)
  if allowed_to_run and conf.log_bodies then
    kong.ctx.plugin.request_body = {}
    local params = kong.request.get_body()

    if params ~= nil then
      kong.ctx.plugin.request_body = remove_sensible_data_from_table(conf, params)
    end
  end
end

function CollectorHandler:body_filter(conf)
end

function CollectorHandler:log(conf)
  local entry = kong.log.serialize()
  entry["request"]["post_data"] = kong.ctx.plugin.request_body
  entry = cjson_safe.encode(entry)

  if not queue then
    create_queue(conf)
  end

  if entry then
    queue:add(entry)
  end
end

return CollectorHandler
