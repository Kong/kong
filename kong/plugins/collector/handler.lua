local basic_serializer = require "kong.plugins.log-serializers.basic"
local BasePlugin = require "kong.plugins.base_plugin"
local BatchQueue = require "kong.tools.batch_queue"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local cjson_safe = require "cjson.safe"
local http = require "resty.http"
local pl_stringx = require "pl.stringx"

local allowed_to_run = true
local queues = {}

local function json_array_concat(entries)
  return "[" .. table.concat(entries, ",") .. "]"
end

local function get_buffer_id(conf)
  return string.format("%s-%s-%s", conf.http_endpoint, conf.service_id, conf.route_id)
end

local function parse_multipart_form_params(body, content_type)
  if not content_type then
    return nil, 'missing content-type'
  end

  local m, err = ngx.re.match(content_type, "boundary=(.+)", "oj")
  if not m or not m[1] or err then
    return nil, "could not find boundary in content type " .. content_type ..
                "error: " .. tostring(err)
  end

  local boundary    = m[1]
  local parts_split = utils.split(body, '--' .. boundary)
  local params      = {}
  local part, from, to, part_value, part_name, part_headers, first_header
  for i = 1, #parts_split do
    part = pl_stringx.strip(parts_split[i])

    if part ~= '' and part ~= '--' then
      from, to, err = ngx.re.find(part, '^\\r$', 'ojm')
      if err or (not from and not to) then
        return nil, nil, "could not find part body. Error: " .. tostring(err)
      end

      part_value   = part:sub(to + 2, #part) -- +2: trim leading line jump
      part_headers = part:sub(1, from - 1)
      first_header = utils.split(part_headers, '\\n')[1]
      if pl_stringx.startswith(first_header:lower(), "content-disposition") then
        local m, err = ngx.re.match(first_header, 'name="(.*?)"', "oj")

        if err or not m or not m[1] then
          return nil, "could not parse part name. Error: " .. tostring(err)
        end

        part_name = m[1]
      else
        return nil, "could not find part name in: " .. part_headers
      end

      params[part_name] = part_value
    end
  end

  return params
end


-- Sends the provided payload (a string) to the configured plugin host
-- @return true if everything was sent correctly, falsy if error
-- @return error message if there was an error
local function send_payload(self, conf, payload)
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


local CollectorHandler = BasePlugin:extend()

CollectorHandler.PRIORITY = 903
CollectorHandler.VERSION = "1.7.5"


local function remove_sensible_data_from_table(a_table, depth)
  local clean = {}
  depth = depth or 1
  local max_depth = 500

  if depth == max_depth then
    -- if we can't remove PII from the whole body we won't send it
    return {}
  end

  if type(a_table) == "string" then
    return {}
  end

  if a_table then
    for key, value in pairs(a_table) do
      if type(value) == "table" then
        clean[key] = remove_sensible_data_from_table(value, depth + 1)
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
  -- we need to store request state before plugins change it
  kong.ctx.plugin.serialized_request = basic_serializer.serialize(ngx)

  if allowed_to_run and conf.log_bodies then
    ngx.req.read_body()
    kong.ctx.plugin.request_body = {}
    local content_type = ngx.req.get_headers(0)["Content-Type"]
    local body = ngx.req.get_body_data()
    local params = {}
    local err
    if type(content_type) == "string" then
      if content_type:find("application/x-www-form-urlencoded", nil, true) then
        params, err = ngx.req.get_post_args()
      elseif content_type:find("multipart/form-data", nil, true) then
        params, err = parse_multipart_form_params(body, content_type)
      elseif content_type:find("application/json", nil, true) then
        params, err = cjson_safe.decode(body)
      end
      if err then
        kong.log.err("Could not parse body data: ", err)
      else
        kong.ctx.plugin.request_body = remove_sensible_data_from_table(params)
      end
    end
  end
end

function CollectorHandler:body_filter(conf)
  if allowed_to_run then
    if conf.log_bodies then
      local chunk = ngx.arg[1]
      local res_body = ngx.ctx.collector and ngx.ctx.collector.res_body or ""
      res_body = res_body .. (chunk or "")

      if ngx.ctx.collector then
        ngx.ctx.collector.res_body = res_body
      end
      -- catch unauth error
      if not ngx.ctx.collector then
        return { status = 403, message = "No API key found in request" }
      end
    end
  else
    kong.log.err("This plugin is intended to work with only Kong Enterprise.")
  end
end

function CollectorHandler:log(conf)
  local entry = kong.ctx.plugin.serialized_request
  local response_entry = basic_serializer.serialize(ngx)
  entry["response"] = response_entry["response"]
  entry["request"]["post_data"] = kong.ctx.plugin.request_body
  entry = cjson.encode(entry)

  local queue_id = get_buffer_id(conf)
  local q = queues[queue_id]
  if not q then
    -- batch_max_size <==> conf.queue_size
    local batch_max_size = conf.queue_size or 1
    local process = function(entries)
      local payload
      if #entries == 1 or batch_max_size == 1 then
        payload = entries[1]
      else
        payload = json_array_concat(entries)
      end
      return send_payload(self, conf, payload)
    end

    local opts = {
      retry_count = conf.retry_count,
      flush_timeout = 1,
      batch_max_size = batch_max_size,
      process_delay = 0,
    }

    local err
    q, err = BatchQueue.new(process, opts)
    if not q then
      kong.log.err("could not create queue: ", err)
      return
    end
    queues[queue_id] = q
  end

  q:add(entry)
end

return CollectorHandler
