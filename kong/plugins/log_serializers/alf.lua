-- ALF serializer module.
-- ALF is the format supported by API Analytics (http://apianalytics.com)
--
-- This module represents _one_ ALF entry, which can have multiple requests entries.
-- # Usage:
--
--   ## Create the ALF like so:
--     local alf = ALFSerializer:new_alf()
--
--   ## Add entries:
--     local n_entries = alf:add_entry(ngx)
--
--   ## Output the ALF with all its entries as JSON:
--     local json_str = alf:to_json_str(service_token)
--
-- - ALF specifications: https://github.com/Mashape/api-log-format
-- - Nginx lua module documentation: http://wiki.nginx.org/HttpLuaModule
-- - ngx_http_core_module: http://wiki.nginx.org/HttpCoreModule#.24http_HEADER

local json = require "cjson"

local EMPTY_ARRAY_PLACEHOLDER = "__empty_array_placeholder__"

local alf_mt = {}
alf_mt.__index = alf_mt

function alf_mt:new_alf()
  local ALF = {
    version = "1.0.0",
    serviceToken = "", -- will be filled by to_json_string()
    har = {
      log = {
        version = "1.2",
        creator = {
          name = "kong-api-analytics-plugin",
          version = "0.1"
        },
        entries = {}
      }
    }
  }

  return setmetatable(ALF, self)
end

-- Transform a key/value lua table into an array of elements with `name`, `value`.
-- Since Lua won't recognize {} as an empty array but an empty object, we need to force it
-- to be an array, hence we will do "[__empty_array_placeholder__]".
-- Then once the ALF will be stringified, we will remove the placeholder so the only left element will be "[]".
-- @param `hash` key/value dictionary to serialize.
-- @param `fn`   Some function to execute at each key iteration, with the key and value as parameters.
-- @return `array` an array, or nil
local function dic_to_array(hash, fn)
  if not fn then fn = function() end end
  local arr = {}
  for k, v in pairs(hash) do
    -- If the key has multiple values, v will be an array of all those values for the same key
    -- hence we have to add multiple entries to the output array for that same key.
    if type(v) ~= "table" then
      v = {v}
    end
    for _, val in ipairs(v) do
      table.insert(arr, { name = k, value = val })
      fn(k, val)
    end
  end

  if #arr > 0 then
    return arr
  else
    return {EMPTY_ARRAY_PLACEHOLDER}
  end
end

-- Round a number to the third decimal.
-- http://lua-users.org/wiki/SimpleRound
local function round(num)
  return math.floor(num * 10^3 + 0.5) / 10^3
end

-- Serialize `ngx` into one ALF entry.
-- For performance reasons, it tries to use the NGINX Lua API instead of
-- ngx_http_core_module when possible.
-- Public for unit testing.
function alf_mt:serialize_entry(ngx)
  -- Extracted data
  local req_headers = ngx.req.get_headers()
  local res_headers = ngx.resp.get_headers()

  local apianalytics_data = ngx.ctx.apianalytics
  local req_body = apianalytics_data.req_body
  local res_body = apianalytics_data.res_body

  local started_at = ngx.ctx.started_at

  -- ALF properties
  -- timers
  local send_time = round(ngx.ctx.proxy_started_at - started_at)
  local wait_time = ngx.ctx.proxy_ended_at - ngx.ctx.proxy_started_at
  local receive_time = apianalytics_data.response_received - ngx.ctx.proxy_ended_at
  -- headers and headers size
  local req_headers_str, res_headers_str = "", ""
  local req_headers_arr = dic_to_array(req_headers, function(k, v) req_headers_str = req_headers_str..k..v end)
  local res_headers_arr = dic_to_array(res_headers, function(k, v) res_headers_str = res_headers_str..k..v end)
  local req_headers_size = string.len(req_headers_str)
  local res_headers_size = string.len(res_headers_str)
  -- values extracted from headers
  local alf_req_mimeType = req_headers["Content-Type"] and req_headers["Content-Type"] or "application/octet-stream"
  local alf_res_mimeType = res_headers["Content-Type"] and res_headers["Content-Type"] or "application/octet-stream"

  return {
    startedDateTime = os.date("!%Y-%m-%dT%TZ", started_at),
    clientIPAddress = ngx.var.remote_addr,
    time = round(send_time + wait_time + receive_time),
    request = {
      method = ngx.req.get_method(),
      url = ngx.var.scheme.."://"..ngx.var.host..ngx.var.uri,
      httpVersion = "HTTP/"..ngx.req.http_version(),
      queryString = dic_to_array(ngx.req.get_uri_args()),
      headers = req_headers_arr,
      headersSize = req_headers_size,
      cookies = {EMPTY_ARRAY_PLACEHOLDER},
      bodySize = string.len(req_body),
      postData = {
        mimeType = alf_req_mimeType,
        params = dic_to_array(ngx.req.get_post_args()),
        text = req_body and req_body or ""
      }
    },
    response = {
      status = ngx.status,
      statusText = "", -- can't find a way to retrieve that
      httpVersion = "", -- can't find a way to retrieve that either
      headers = res_headers_arr,
      headersSize = res_headers_size,
      cookies = {EMPTY_ARRAY_PLACEHOLDER},
      bodySize = tonumber(ngx.var.body_bytes_sent),
      redirectURL = "",
      content = {
        size = tonumber(ngx.var.body_bytes_sent),
        mimeType = alf_res_mimeType,
        text = res_body and res_body or ""
      }
    },
    cache = {},
    timings = {
      send = round(send_time),
      wait = round(wait_time),
      receive = round(receive_time),
      blocked = -1,
      connect = -1,
      dns = -1,
      ssl = -1
    }
  } -- end of entry
end

function alf_mt:add_entry(ngx)
  table.insert(self.har.log.entries, self:serialize_entry(ngx))
  return table.getn(self.har.log.entries)
end

function alf_mt:to_json_string(token)
  if not token then
    error("API Analytics serviceToken required", 2)
  end

  -- inject token
  self.serviceToken = token

  local str = json.encode(self)
  return str:gsub("\""..EMPTY_ARRAY_PLACEHOLDER.."\"", ""):gsub("\\/", "/")
end

function alf_mt:flush_entries()
  self.har.log.entries = {}
end

return alf_mt
