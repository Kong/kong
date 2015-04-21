-- ALF serializer module.
-- ALF is the format supported by API Analytics (http://apianalytics.com)
--
-- - ALF specifications: https://github.com/Mashape/api-log-format
-- - Nginx lua module documentation: http://wiki.nginx.org/HttpLuaModule
-- - ngx_http_core_module: http://wiki.nginx.org/HttpCoreModule#.24http_HEADER

local EMPTY_ARRAY_PLACEHOLDER = "__empty_array_placeholder__"

local alf_mt = {}
alf_mt.__index = alf_mt

local ALF = {
  version = "1.0.0",
  serviceToken = "",
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

-- Transform a key/value lua table into an array of elements with `name`, `value`
-- Since Lua won't recognize {} as an empty array but an empty object, we need to force it
-- to be an array, hence we will do "[__empty_array_placeholder__]".
-- Then once the ALF will be stringified, we will remove the placeholder so the only left element will be "[]".
-- @param hash key/value dictionary to serialize
-- @return an array, or nil
local function dic_to_array(hash)
  local arr = {}
  for k, v in pairs(hash) do
    table.insert(arr, { name = k, value = v })
  end

  if #arr > 0 then
    return arr
  else
    return {EMPTY_ARRAY_PLACEHOLDER}
  end
end

-- Serialize into one ALF entry
-- For performance reasons, it tries to use the NGINX Lua API
-- instead of ngx_http_core_module when possible.
function alf_mt:serialize_entry(ngx)
  -- Extracted data
  local req_headers = ngx.req.get_headers()
  local res_headers = ngx.resp.get_headers()

  local req_body = ngx.ctx.req_body
  local res_body = ngx.ctx.res_body

  -- ALF format
  local alf_req_mimeType = req_headers["Content-Type"] and req_headers["Content-Type"] or "application/octet-stream"
  local alf_res_mimeType = res_headers["Content-Type"] and res_headers["Content-Type"] or "application/octet-stream"
  local alf_req_bodySize = req_headers["Content-Length"] and req_headers["Content-Length"] or 0
  local alf_res_bodySize = res_headers["Content-Length"] and res_headers["Content-Length"] or 0

  return {
    startedDateTime = os.date("!%Y-%m-%dT%TZ", ngx.req.start_time()),
    clientIPAddress = ngx.var.remote_addr,
    time = 3,
    -- REQUEST
    request = {
      method = ngx.req.get_method(),
      url = ngx.var.scheme.."://"..ngx.var.host..ngx.var.uri,
      httpVersion = "HTTP/"..ngx.req.http_version(),
      queryString = dic_to_array(ngx.req.get_uri_args()),
      headers = dic_to_array(req_headers),
      headersSize = 10,
      cookies = {EMPTY_ARRAY_PLACEHOLDER},
      bodySize = tonumber(alf_req_bodySize),
      content = {
        size = tonumber(ngx.var.request_length),
        mimeType = alf_req_mimeType,
        text = req_body and req_body or ""
      }
    },
    -- RESPONSE
    response = {
      status = ngx.status,
      statusText = "",
      httpVersion = "",
      headers = dic_to_array(res_headers),
      headersSize = 10,
      cookies = {EMPTY_ARRAY_PLACEHOLDER},
      bodySize = tonumber(alf_res_bodySize),
      redirectURL = "",
      content = {
        size = tonumber(ngx.var.bytes_sent),
        mimeType = alf_res_mimeType,
        text = res_body and res_body or ""
      }
    },
    cache = {},
    -- TIMINGS
    timings = {
      send = 1,
      wait = 1,
      receive = 1,
      blocked = 0,
      connect = 0,
      dns = 0,
      ssl = 0
    }
  } -- end of entry
end

function alf_mt:add_entry(ngx)
  table.insert(self.har.log.entries, self:serialize_entry(ngx))
end

function alf_mt:to_json_string(token)
  if not token then
    error("API Analytics serviceToken required", 2)
  end

  local cjson = require "cjson"

  -- inject token
  self.serviceToken = token

  local str = cjson.encode(self)
  return str:gsub("\""..EMPTY_ARRAY_PLACEHOLDER.."\"", ""):gsub("\\/", "/")
end

function alf_mt:flush_entries()
  self.har.log.entries = {}
end

return setmetatable(ALF, alf_mt)
