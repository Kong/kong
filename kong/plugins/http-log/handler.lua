local Queue = require "kong.tools.queue"
local cjson = require "cjson"
local url = require "socket.url"
local http = require "resty.http"
local sandbox = require "kong.tools.sandbox".sandbox
local kong_meta = require "kong.meta"


local kong = kong
local ngx = ngx
local encode_base64 = ngx.encode_base64
local tostring = tostring
local tonumber = tonumber
local fmt = string.format
local pairs = pairs
local max = math.max


local sandbox_opts = { env = { kong = kong, ngx = ngx } }

-- Create a function that concatenates multiple JSON objects into a JSON array.
-- This saves us from rendering all entries into one large JSON string.
-- Each invocation of the function returns the next bit of JSON, i.e. the opening
-- bracket, the entries, delimiting commas and the closing bracket.
local function make_json_array_payload_function(conf, entries)
  if conf.queue.max_batch_size == 1 then
    return #entries[1], entries[1]
  end

  local nentries = #entries

  local content_length = 1
  for i = 1, nentries do
    content_length = content_length + #entries[i] + 1
  end

  local i = 0
  local last = max(2, nentries * 2 + 1)
  return content_length, function()
    i = i + 1

    if i == 1 then
      return '['

    elseif i < last then
      return i % 2 == 0 and entries[i / 2] or ','

    elseif i == last then
      return ']'
    end
  end
end


local parsed_urls_cache = {}
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
  local content_length, payload
  if conf.queue.max_batch_size == 1 then
    assert(
      #entries == 1,
      "internal error, received more than one entry in queue handler even though max_batch_size is 1"
    )
    content_length = #entries[1]
    payload = entries[1]
  else
    content_length, payload = make_json_array_payload_function(conf, entries)
  end

  local method = conf.method
  local timeout = conf.timeout
  local keepalive = conf.keepalive
  local content_type = conf.content_type
  local http_endpoint = conf.http_endpoint

  local parsed_url = parse_url(http_endpoint)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)
  local userinfo = parsed_url.userinfo

  local httpc = http.new()
  httpc:set_timeout(timeout)

  local headers = {
    ["Content-Type"] = content_type,
    ["Content-Length"] = content_length,
    ["Authorization"] = userinfo and "Basic " .. encode_base64(userinfo) or nil
  }
  if conf.headers then
    for h, v in pairs(conf.headers) do
      headers[h] = headers[h] or v -- don't override Host, Content-Type, Content-Length, Authorization
    end
  end

  local log_server_url = fmt("%s://%s:%d%s", parsed_url.scheme, host, port, parsed_url.path)

  local res, err = httpc:request_uri(log_server_url, {
    method = method,
    headers = headers,
    body = payload,
    keepalive_timeout = keepalive,
    ssl_verify = false,
  })
  if not res then
    return nil, "failed request to " .. host .. ":" .. tostring(port) .. ": " .. err
  end

  -- always read response body, even if we discard it without using it on success
  local response_body = res.body

  kong.log.debug(fmt("http-log sent data log server, %s:%s HTTP status %d",
    host, port, res.status))

  if res.status < 300 then
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


-- Create a queue name from the same legacy parameters that were used in the
-- previous queue implementation.  This ensures that http-log instances that
-- have the same log server parameters are sharing a queue.  It deliberately
-- uses the legacy parameters to determine the queue name, even though they may
-- be nil in newer configurations.  Note that the modernized queue related
-- parameters are not included in the queue name determination.
local function make_queue_name(conf)
  return fmt("%s:%s:%s:%s:%s:%s",
    conf.http_endpoint,
    conf.method,
    conf.content_type,
    conf.timeout,
    conf.keepalive,
    conf.retry_count,
    conf.queue_size,
    conf.flush_timeout)
end


function HttpLogHandler:log(conf)
  if conf.custom_fields_by_lua then
    local set_serialize_value = kong.log.set_serialize_value
    for key, expression in pairs(conf.custom_fields_by_lua) do
      set_serialize_value(key, sandbox(expression, sandbox_opts)())
    end
  end

  local queue_conf = Queue.get_plugin_params("http-log", conf, make_queue_name(conf))
  kong.log.debug("Queue name automatically configured based on configuration parameters to: ", queue_conf.name)

  local ok, err = Queue.enqueue(
    queue_conf,
    send_entries,
    conf,
    cjson.encode(kong.log.serialize())
  )
  if not ok then
    kong.log.err("Failed to enqueue log entry to log server: ", err)
  end
end

return HttpLogHandler
