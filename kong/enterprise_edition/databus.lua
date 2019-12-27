local cjson = require "cjson"

local http = require "resty.http"

local utils = require "kong.tools.utils"

local string_gsub = string.gsub

-- Case insensitive lookup function, returns the value and the original key. Or
-- if not found nil and the search key
-- @usage -- sample usage
-- local test = { SoMeKeY = 10 }
-- print(lookup(test, "somekey"))  --> 10, "SoMeKeY"
-- print(lookup(test, "NotFound")) --> nil, "NotFound"
local function lookup(t, k)
  local ok = k
  if type(k) ~= "string" then
    return t[k], k
  else
    k = k:lower()
  end
  for key, value in pairs(t) do
    if tostring(key):lower() == k then
      return value, key
    end
  end
  return nil, ok
end

local function as_body(data, opts)
  local body = ""

  local headers = opts.headers or {}

  -- build body
  local content_type, content_type_name = lookup(headers, "Content-Type")
  content_type = content_type or ""
  local t_body_table = type(data) == "table"
  if string.find(content_type, "application/json") and t_body_table then
    body = cjson.encode(data)
  elseif string.find(content_type, "www-form-urlencoded", nil, true) and t_body_table then
    body = utils.encode_args(data, true, opts.no_array_indexes)
  elseif string.find(content_type, "multipart/form-data", nil, true) and t_body_table then
    local form = data
    local boundary = "8fd84e9444e3946c"

    for k, v in pairs(form) do
      body = body .. "--" .. boundary .. "\r\nContent-Disposition: form-data; name=\"" .. k .. "\"\r\n\r\n" .. tostring(v) .. "\r\n"
    end

    if body ~= "" then
      body = body .. "--" .. boundary .. "--\r\n"
    end

    local clength = lookup(headers, "content-length")
    if not clength then
      headers["content-length"] = #body
    end

    if not content_type:find("boundary=") then
      headers[content_type_name] = content_type .. "; boundary=" .. boundary
    end

  end

  return body
end

-- XXX: Ideally we make this a performant one
local function request(url, method, data, headers)
  local body = nil
  if method == "GET" then
    url = url .. '?' .. utils.encode_args(data)
  else
    if data and not lookup(headers, "content-type") then
      headers["Content-Type"] = "multipart/form-data"
    end
    body = as_body(data, { headers = headers })
  end

  local client = http.new()
  local params = {
    method = method,
    body = body,
    headers = headers,
    ssl_verify = false,
  }

  ngx.log(ngx.ERR, [[self:request]], require("inspect")({url, params}))
  return client:request_uri(url, params)
end

local function format(text, args)
  return string_gsub(text, "({{([^}]+)}})", function(whole, match)
    return args[match] or ""
  end)
end


local kong = kong

local _M = {}

local events = {}

-- Not sure if this is good enough. Holds references to callbacks by id so
-- we can properly unregister worker events
local references = {}

_M.enabled = function()
  return kong.configuration.databus_enabled
end

_M.publish = function(source, event, help)
  if not _M.enabled() then return end
  if not events[source] then events[source] = {} end
  events[source][#events[source] + 1] = { event, help }
end

_M.register = function(entity)
  if not _M.enabled() then return end
  local callback = _M.callback(entity)
  local source = entity.source
  local event = entity.event
  -- register null event
  if event == ngx.null then
    event = nil
  end

  references[entity.id] = callback

  return kong.worker_events.register(callback, "dbus:" .. source, event)
end

_M.unregister = function(entity)
  if not _M.enabled() then return end
  local callback = references[entity.id]
  local source = entity.source
  local event = entity.event

  -- XXX This good? maybe check if the unregister was succesful
  references[entity.id] = nil

  return kong.worker_events.unregister(callback, "dbus:" .. source, event)
end


-- XXX: Find out why these are blocking on the context!
_M.emit = function(source, event, data)
  if not _M.enabled() then return end
  return kong.worker_events.post_local("dbus:" .. source, event, data)
end

_M.list = function()
  return events
end

_M.callback = function(entity)
  return _M.handlers[entity.handler](entity.config)
end


_M.handlers = {
  webhook = function(config)
    return function(data, event, source, pid)
      data.event = event
      data.source = source

      local payload = {}
      if config.payload_format then
        for k, v in pairs(config.payload) do
          payload[k] = format(v, data)
        end
      else
        payload = config.payload
      end

      local headers = {}
      if config.headers_format then
        for k, v in pairs(config.headers) do
          headers[k] = format(v, data)
        end
      else
        headers = config.headers
      end

      ngx.log(ngx.ERR, [[self: event data ]], require("inspect")({data}))
      local res, err = request(config.url, config.method, payload, headers)
      ngx.log(ngx.ERR, [[self: response: ]], require("inspect")({res and res.status or nil, err}))
    end
  end,

  -- This would be a specialized helper easier to configure than a webhook
  -- even though slack would use a webhook
  slack = function(config)
    return function(data, event, source, pid)
      ngx.log(ngx.ERR, [[self:slack]], require("inspect")({config, data, event, source, pid}))
    end
  end,

  log = function(config)
    return function(data, event, source, pid)
      -- Maybe this should be a proper "log", something useful
      ngx.log(ngx.ERR, [[self:logggg]], require("inspect")({config, data, event, source, pid}))
    end
  end,
}

return _M
