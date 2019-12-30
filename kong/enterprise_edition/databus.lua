local cjson = require "cjson"
local inspect = require "inspect"
local template = require "resty.template"

local request = require "kong.enterprise_edition.utils".request

local fmt = string.format
local md5 = ngx.md5
local ngx_null = ngx.null

-- XXX TODO:
-- payload webhook, can it be just a JSON blob?
-- make slack nicer
-- refactor http request into something useful
-- use proper templating instead of regexing
-- (does not support compount foo.bar fields)

local _M = {}

local events = {}

-- Not sure if this is good enough. Holds references to callbacks by id so
-- we can properly unregister worker events
local references = {}

_M.enabled = function()
  return kong.configuration.databus_enabled
end

_M.crud = function(data)
  if data.operation == "delete" then
    _M.unregister(data.entity)
  elseif data.operation == "update" then
    _M.unregister(data.old_entity)
    _M.register(data.entity)
  elseif data.operation == "create" then
    _M.register(data.entity)
  end
end

_M.publish = function(source, event, opts)
  opts = opts or {}
  if not _M.enabled() then return end
  if not events[source] then events[source] = {} end
  events[source][event] = {
    description = opts.description,
    fields = opts.fields,
    signature = opts.signature,
  }
  return true
end

_M.register = function(entity)
  if not _M.enabled() then return end
  local callback = _M.callback(entity)
  local source = entity.source
  local event = entity.event ~= ngx_null and entity.event or nil

  references[entity.id] = callback

  return kong.worker_events.register(callback, "dbus:" .. source, event)
end

_M.unregister = function(entity)
  if not _M.enabled() then return end
  local callback = references[entity.id]
  local source = entity.source
  local event = entity.event ~= ngx_null and entity.event or nil

  -- XXX This good? maybe check if the unregister was succesful
  references[entity.id] = nil

  return kong.worker_events.unregister(callback, "dbus:" .. source, event)
end

_M.emit = function(source, event, data)
  if not _M.enabled() then return end
  return kong.worker_events.post_local("dbus:" .. source, event, data)
end

_M.list = function()
  return events
end

_M.signature = function(source, event, data)
  local hash
  local signature_fields = events[source] and events[source][event] and
                           events[source][event].signature
  if signature_fields then
    local signature_data = {}
    for _, k in pairs(signature_fields) do
      signature_data[k] = data[k]
    end
    hash = md5(cjson.encode(signature_data))
  else
    hash = md5(cjson.encode(data))
  end

  return hash
end

-- XXX: hack to get asynchronous execution of callbacks. Check with thijs
-- about this.
local BatchQueue = require "kong.tools.batch_queue"

local process_callback = function(batch)
  local entry = batch[1]
  return entry.callback(entry.data, entry.event, entry.source, entry.pid)
end

local queue = BatchQueue.new(process_callback, {
  batch_max_size = 1
})

_M.callback = function(entity)
  local callback = _M.handlers[entity.handler](entity, entity.config)
  local wrap = function(data, event, source, pid)
    local source = source:gsub("^dbus:", "")

    local ttl = entity.snooze ~= ngx_null and entity.snooze or nil
    local on_change = entity.on_change ~= ngx_null and entity.on_change or nil

    if ttl or on_change then
      -- kong:cache is used as a blacklist of events to not process:
      -- > on_change: only enqueue an event that has changed (looks different)
      -- > snooze: like an alarm clock, disable event for N seconds
      local cache_key = fmt("dbus:%s:%s:%s", entity.id, source, event)

      -- append digest of relevant fields in data to filter by same-ness
      if on_change then
        cache_key = cache_key .. ":" .. _M.signature(source, event, data)
      end

      local _, _, hit_lvl = kong.cache:get(cache_key, nil, function(ttl)
        return true, nil, ttl
      end, ttl)

      -- either in L1 or L2, this event is to be ignored
      if hit_lvl ~= 3 then
        kong.log.warn("ignoring dbus event: ", cache_key)
        return
      end
    end

    local blob = {
      callback = callback,
      data = data,
      event = event,
      source = source,
      pid = pid,
    }

    queue:add(blob)
  end

  return wrap
end


_M.handlers = {
  webhook = function(entity, config)
    return function(data, event, source, pid)
      local payload, body, headers

      data.event = event
      data.source = source

      if config.payload and config.payload ~= ngx_null then
        if config.payload_format then
          payload = {}
          for k, v in pairs(config.payload) do
            payload[k] = template.compile(v)(data)
          end
        else
          payload = config.payload
        end
      end

      if config.body and config.body ~= ngx_null then
        if config.body_format then
          body = template.compile(config.body)(data)
        else
          body = config.body
        end
      end

      if config.headers and config.headers ~= ngx_null then
        if config.headers_format then
          headers = {}
          for k, v in pairs(config.headers) do
            headers[k] = template.compile(v)(data)
          end
        else
          headers = config.headers
        end
      end

      kong.log.debug("webhook event data: ", inspect({data, event, source, pid}))
      local res, err = request(config.url, {
        method = config.method,
        data = payload,
        body = body,
        headers = headers
      })
      kong.log.debug("response: ", inspect({res and res.status or nil, err}))
      return not err
    end
  end,

  -- This would be a specialized helper easier to configure than a webhook
  -- even though slack would use a webhook
  slack = function(entity, config)
    return function(data, event, source, pid)
      kong.log.debug("slack event data: ", inspect({data, event, source, pid}))
      kong.log.debug("slack callback not implemented")
      return true
    end
  end,

  log = function(entity, config)
    return function(data, event, source, pid)
      kong.log.notice("log callback ", inspect({event, source, data, pid}))
      return true
    end
  end,

  lambda = function(entity, config)
    local functions = {}

    -- limit execution context
    --local helper_ctx = {
    --  require = require,
    --  type = type,
    --  print = print,
    --  pairs = pairs,
    --  ipairs = ipairs,
    --  inspect = inspect,
    --  request = request,
    --  kong = kong,
    --  ngx = ngx,
    --  -- ... anything else useful ?
    --}
    -- or allow _anything_
    local helper_ctx = _G

    local chunk_name = "dbus:" .. entity.id

    for i, fn_str in ipairs(config.functions) do
      -- each function has its own context. We could let them share context
      -- by not defining fn_ctx and just passing helper_ctx
      local fn_ctx = {}
      setmetatable(fn_ctx, { __index = helper_ctx })
      -- t -> only text chunks
      local fn = load(fn_str, chunk_name .. ":" .. i, "t", fn_ctx)     -- load
      local _, actual_fn = pcall(fn)
      table.insert(functions, actual_fn)
    end

    return function(data, event, source, pid)
      -- reduce on functions with data
      local err
      for _, fn in ipairs(functions) do
        data, err = fn(data, event, source, pid)
      end
      return not err
    end
  end,
}

-- accessors to ease unit testing
_M.events = events
_M.references = references
_M.queue = queue

return _M
