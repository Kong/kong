local Queue = require "kong.tools.queue"
local cjson = require "cjson"
local url = require "socket.url"
local http = require "resty.http"
local table_clear = require "table.clear"
local sandbox = require "kong.tools.sandbox".sandbox
local kong_meta = require "kong.meta"


local kong = kong
local ngx = ngx
local encode_base64 = ngx.encode_base64
local tostring = tostring
local tonumber = tonumber
local concat = table.concat
local fmt = string.format
local pairs = pairs


local sandbox_opts = { env = { kong = kong, ngx = ngx } }


local parsed_urls_cache = {}
local headers_cache = {}
local params_cache = {
  ssl_verify = false,
  headers = headers_cache,
}


local function json_array_concat(entries)
  return "[" .. concat(entries, ",") .. "]"
end


-- Parse host url.
-- @param `url` host url
-- @return `parsed_url` a table with host details:
-- scheme, host, port, path, query, userinfo
local function parse_url(host_url)
  local parsed_url = parsed_urls_cache[host_url]

  if parsed_url then
    return parsed_url
  end

  parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then
      parsed_url.port = 80
    elseif parsed_url.scheme == "https" then
      parsed_url.port = 443
    end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end

  parsed_urls_cache[host_url] = parsed_url

  return parsed_url
end


-- Sends the provided entries to the configured plugin host
-- @return true if everything was sent correctly, falsy if error
-- @return error message if there was an error
local function send_entries(conf, entries)
  local payload = conf.queue.batch_max_size == 1
    and entries[1]
    or json_array_concat(entries)

  local method = conf.method
  local timeout = conf.timeout
  local keepalive = conf.keepalive
  local content_type = conf.content_type
  local http_endpoint = conf.http_endpoint

  local parsed_url = parse_url(http_endpoint)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)

  local httpc = http.new()
  httpc:set_timeout(timeout)

  table_clear(headers_cache)
  if conf.headers then
    for h, v in pairs(conf.headers) do
      headers_cache[h] = v
    end
  end

  headers_cache["Host"] = parsed_url.host
  headers_cache["Content-Type"] = content_type
  headers_cache["Content-Length"] = #payload
  if parsed_url.userinfo then
    headers_cache["Authorization"] = "Basic " .. encode_base64(parsed_url.userinfo)
  end

  params_cache.method = method
  params_cache.body = payload
  params_cache.keepalive_timeout = keepalive

  local url = fmt("%s://%s:%d%s", parsed_url.scheme, parsed_url.host, parsed_url.port, parsed_url.path)

  -- note: `httpc:request` makes a deep copy of `params_cache`, so it will be
  -- fine to reuse the table here
  local res, err = httpc:request_uri(url, params_cache)
  if not res then
    return nil, "failed request to " .. host .. ":" .. tostring(port) .. ": " .. err
  end

  -- always read response body, even if we discard it without using it on success
  local response_body = res.body

  ngx.log(ngx.DEBUG, string.format("http-log sent data to upstream, %s:%s HTTP status %d",
    host, port, res.status))

  if res.status < 400 then
    return true
  else
    return nil, "request to " .. host .. ":" .. tostring(port)
      .. " returned status code " .. tostring(res.status) .. " and body "
      .. response_body
  end
end


local HttpLogHandler = {
  PRIORITY = 12,
  VERSION = kong_meta.version,
}


function get_queue_params(config)
  local key = config.__key__
  local queue = unpack({config.queue or {}})
  if config.retry_count then
    ngx.log(ngx.WARN, string.format(
      "deprecated `retry_count` parameter in plugin %s ignored",
      key))
  end
  if config.queue_size then
    ngx.log(ngx.WARN, string.format(
      "deprecated `queue_size` parameter in plugin %s converted to `queue.batch_max_size`",
      key))
    queue.batch_max_size = config.queue_size
  end
  if config.flush_timeout then
    ngx.log(ngx.WARN, string.format(
      "deprecated `flush_timeout` parameter in plugin %s converted to `queue.max_delay`",
      key))
    queue.max_delay = config.flush_timeout
  end
  if not queue.name then
    queue.name = key
  end
  return queue
end


function HttpLogHandler:log(conf)
  if conf.custom_fields_by_lua then
    local set_serialize_value = kong.log.set_serialize_value
    for key, expression in pairs(conf.custom_fields_by_lua) do
      set_serialize_value(key, sandbox(expression, sandbox_opts)())
    end
  end

  local queue = Queue.get(
    "http-log",
    function(entries) return send_entries(conf, entries) end,
    get_queue_params(conf)
  )

  queue:add(cjson.encode(kong.log.serialize()))
end

-- for testing
HttpLogHandler.__get_queue_params = get_queue_params

return HttpLogHandler
