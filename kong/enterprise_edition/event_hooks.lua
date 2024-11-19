-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe"
local tx = require "pl/tablex"
local to_hex = require "resty.string".to_hex

local Queue = require "kong.tools.queue"
local queue_schema_definition = require "kong.tools.queue_schema"
local Schema = require "kong.db.schema"
local sandbox = require "kong.tools.sandbox"
local request = require "kong.enterprise_edition.utils".request
local normalize_table = require "kong.enterprise_edition.utils".normalize_table
local balancer  = require "kong.runloop.balancer"

local fmt = string.format
local ipairs = ipairs
local pairs = pairs
local ngx_null = ngx.null
local md5 = ngx.md5
local hmac_sha1 = ngx.hmac_sha1
local timer_at = ngx.timer.at

local GLOBAL_QUERY_OPTS = { workspace = ngx_null, show_ws_id = true }

local QUEUE_OPTS = {
  max_batch_size = 1,
  max_coalescing_delay = 0,
  max_entries = 10000,
}

-- Make sure that our queue options are valid according to the common queue schema (KAG-1760)
local queue_schema = assert(Schema.new(queue_schema_definition))
QUEUE_OPTS = queue_schema:process_auto_fields(QUEUE_OPTS)
local ok, err = queue_schema:validate(QUEUE_OPTS)
assert(ok, "Invalid QUEUE_OPTS: " .. require("inspect")(err))
QUEUE_OPTS.name = "event-hooks"
QUEUE_OPTS.max_bytes = nil

-- XXX Somehow initializing this fails when kong runs on stream only. Something
-- missing on ngx.location
local template

local _M = {}
local initialized = false

local events = {}

-- Holds a map of references to callbacks by id to unregister worker events
local references = {}


local function prefix(source)
  return "event-hooks:" .. source
end


local function unprefix(source)
  return source:gsub("^event%-hooks%:", "", 1)
end


_M.enabled = function()
  return kong.configuration.event_hooks_enabled
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

  -- ping if available
  if _M.has_ping(data.entity) then
    _M.enqueue({
      callback = _M.ping,
      args = { data.entity, data.operation },
    })
  end
end


_M.publish = function(source, event, opts)
  if not source then
    return nil
  end

  if not events[source] then
    events[source] = {}
  end

  opts = opts or {}

  events[source][event] = {
     description = opts.description,
     fields = opts.fields,
     unique = opts.unique,
  }

  return true
end


_M.has_ping = function(entity)
  return _M.handlers[entity.handler](entity, entity.config).ping
end


_M.ping = function(entity, operation)
  local handler = _M.handlers[entity.handler](entity, entity.config)

  if not handler.ping then
    return nil, fmt("handler '%s' does not support 'ping'", entity.handler)
  end

  return handler.ping(operation)
end


_M.register = function(entity)
  if not _M.enabled() then
    return
  end

  local source = entity.source
  local event = entity.event ~= ngx_null and entity.event or nil
  local callback = references[entity.id]

  if callback then
    kong.worker_events.unregister(callback, prefix(source), event)
  end

  callback = _M.callback(entity)
  references[entity.id] = callback

  return kong.worker_events.register(callback, prefix(source), event)
end


_M.unregister = function(entity)
  if not _M.enabled() then
    return
  end

  local callback = references[entity.id]
  local source = entity.source
  local event = entity.event ~= ngx_null and entity.event or nil

  references[entity.id] = nil

  return kong.worker_events.unregister(callback, prefix(source), event)
end


_M.unregister_all = function()
  if not _M.enabled() then
    return
  end

  for _, callback in pairs(references) do
    kong.worker_events.unregister(callback)
  end
end

local function field_digest(source, event, data)
  local fields = events[source] and events[source][event] and
                 events[source][event].unique

  return _M.digest(data, { fields = fields })
end


local function _check(source, event)
  if not events[source] then
    return nil, fmt("source '%s' is not registered", source)
  end

  local event = event ~= ngx_null and event or nil
  if event and not events[source][event] then
    return nil, fmt("source '%s' has no '%s' event", source, event)
  end

  return true
end

_M.emit = function(source, event, data, local_only)
  if not _M.enabled() then
    return
  end

  local res, err = _check(source, event)
  if not res then
    return nil, err
  end

  if local_only then
    return kong.worker_events.post_local(prefix(source), event, data)
  end

  local digest = field_digest(source, event, data)
  local unique = (source ~= 'crud' and source ~= 'dao:crud') and source .. ":" .. event .. ":" .. digest

  return kong.worker_events.post(prefix(source), event, data, unique)
end


_M.list = function()
  return events
end


-- Not to be used for security signing. This function is only used for
-- differentiating different data payloads for caching and deduplicating
-- purposes
_M.digest = function(data, opts)
  local opts = opts or {}
  local fields = opts.fields
  local data = fields and tx.intersection(data, tx.makeset(fields)) or data

  -- Ensure the data is valid JSON
  local _, err = cjson.encode(data)
  if err then
    return nil, err
  end

  return md5(normalize_table(data))
end


local process_callback = function(config, batch)
  local entry = batch[1]
  -- not so easy to parse:
  -- pok: pcall ok
  -- cres_or_perr: pcall err or callback result
  -- cerr: callback err
  local pok, cres_or_perr, cerr = pcall(entry.callback, unpack(entry.args))

  if not pok then
    kong.log.err(cres_or_perr)
    -- not ok, no result, pcall error
    return nil, cres_or_perr
  end

  return cres_or_perr, cerr
end

_M.enqueue = function(entry)
  Queue.enqueue(QUEUE_OPTS, process_callback, nil, entry)
end

_M.callback = function(entity)
  local callback = _M.handlers[entity.handler](entity, entity.config).callback
  local wrap = function(data, event, source, pid)
    local ttl = entity.snooze ~= ngx_null and entity.snooze or nil
    local on_change = entity.on_change ~= ngx_null and entity.on_change or nil

    local source = unprefix(source)

    if ttl or on_change then
      -- kong:cache is used as a blacklist of events to not process:
      -- > on_change: only enqueue an event that has changed (looks different)
      -- > snooze: like an alarm clock, disable event for N seconds
      local cache_key = fmt("event_hooks:%s:%s:%s", entity.id, source, event)
      local digest, err = field_digest(source, event, data)

      if err then
        kong.log.err(fmt("cannot serialize '%s:%s' event data. err: '%s'. " ..
                         "Ignoring on_change/snooze for this event-hook",
                         source, event, err))
      else
        -- append digest of relevant fields in data to filter by same-ness
        if on_change and ttl then
          cache_key = cache_key .. ":" .. digest
        end

        local c_digest, _, hit_lvl = kong.cache:get(cache_key, nil, function(ttl)
          return digest, nil, ttl
        end, ttl)


        -- either in L1 or L2, this event might be ignored
        if hit_lvl ~= 3 then
          -- for on_change only, compare digest with cached digest
          if on_change and not ttl then
            -- same, ignore
            if c_digest == digest then
              kong.log.warn("ignoring event_hooks event: ", cache_key)

              return
            -- update digest
            else
              kong.cache.mlcache.lru:set(cache_key, digest)
            end

          else
            kong.log.warn("ignoring event_hooks event: ", cache_key)

            return
          end
        end
      end
    end

    local blob = {
      callback = callback,
      args = { data, event, source, pid },
    }

    return _M.enqueue(blob)
  end

  return wrap
end

_M.reconfigure = function()
  _M.unregister_all()

  local page_size
  if kong.db.event_hooks.pagination then
    page_size = kong.db.event_hooks.pagination.page_size
  end

  for entity, err in kong.db.event_hooks:each(page_size, GLOBAL_QUERY_OPTS) do
    if err then
      kong.log.err(err)
    else
      _M.register(entity)
    end
  end
end

_M.test = function(entity, data)
  -- Get an unwrapped callback, since we want it sync
  local callback = _M.handlers[entity.handler](entity, entity.config).callback

  local blob = {
      callback = callback,
      args = { data, entity.event, entity.source, 42 },
  }

  return process_callback({blob})
end

local function sign_body(secret)
  return function(body)
    return "sha1", to_hex(hmac_sha1(secret, body))
  end
end

_M.register_events = function(events_handler)
  if not _M.enabled() or initialized then
    return
  end

  local dao_adapter = function(data)
    return {
      entity = data.entity,
      old_entity = data.old_entity,
      schema = data.schema and data.schema.name,
      operation = data.operation,
    }
  end

  -- publish all kong events
  local operations = { "create", "update", "delete" }
  for _, op in ipairs(operations) do
    _M.publish("dao:crud", op, {
      fields = { "operation", "entity", "old_entity", "schema" },
      adapter = dao_adapter,
    })
  end

  for name, _ in pairs(kong.db.daos) do
    _M.publish("crud", name, {
      fields = { "operation", "entity", "old_entity", "schema" },
      adapter = dao_adapter,
    })

    for _, op in ipairs(operations) do
      _M.publish("crud", name .. ":" .. op, {
        fields = { "operation", "entity", "old_entity", "schema" },
        adapter = dao_adapter,
      })
    end
  end

  events_handler.register(function(data, event, source, pid)
    local ok, err = _M.emit(source, event, dao_adapter(data))
    if not ok then
      kong.log.warn("failed to emit event: ", err)
    end
  end, "crud")

  events_handler.register(function(data, event, source, pid)
    local ok, err = _M.emit(source, event, dao_adapter(data))
    if not ok then
      kong.log.warn("failed to emit event: ", err)
    end
  end, "dao:crud")

  events_handler.register(_M.crud, prefix("crud"), "event_hooks")

  events_handler.register(_M.reconfigure, "declarative", "reconfigure")

  -- register a callback to trigger an event_hook balanacer health
  -- event
  balancer.subscribe_to_healthcheck_events(function(upstream_id, ip, port, hostname, health)
    local ok, err = _M.emit("balancer", "health", {
      upstream_id = upstream_id,
      ip = ip,
      port = port,
      hostname = hostname,
      health = health,
    })
    if not ok then
      kong.log.warn("failed to emit event: ", err)
    end
  end)

  _M.publish("balancer", "health", {
    fields = { "upstream_id", "ip", "port", "hostname", "health" },
  })
  initialized = true

  -- XXX not so sure this timer is good? the idea is to not hog kong
  -- on startup for this secondary feature
  timer_at(0, function()
    local page_size
    if kong.db.event_hooks.pagination then
      page_size = kong.db.event_hooks.pagination.page_size
    end

    for entity, err in kong.db.event_hooks:each(page_size, GLOBAL_QUERY_OPTS) do
      if err then
        kong.log.err(err)
      else
        _M.register(entity)
      end
    end
  end)
end

-- a table of handlers that holds initializer functions for every handler
--  > Each entry must be a function that returns a handler
--  > A handler is composed of a set of functions (callback, ping)
--  > These functions are called asyncronously on a batch, so they
--    must return ok, result, error, ie:
--      return nil, 42
--      return false, nil, "some error"

_M.handlers = {
  -- Simple and opinionated webhook. No bells and whistles, 0 config
  --    > method POST
  --    > content-type: application/json
  --    > body: json(data)
  --    > arbitrary headers
  --    > can be signed
  webhook = function(entity, config)

    return {
      callback = function(data, event, source, pid)
        local headers = config.headers ~= ngx_null and config.headers or {}
        local method = "POST"

        headers['content-type'] = "application/json"
        data.event = event
        data.source = source

        local body, err = cjson.encode(data)
        if err then
          error(err)
        end

        local res, err = request(config.url, {
          method = method,
          body = body,
          sign_with = config.secret and config.secret ~= ngx_null and
                      sign_body(config.secret),
          headers = headers,
          ssl_verify = config.ssl_verify,
        })

        if not err then
          return true, {
            body = res.body,
            headers = res.headers,
            status = res.status
          }
        end

        return nil, err
      end,

      ping = function(operation)
        local headers = config.headers ~= ngx_null and config.headers or {}
        local method = "POST"

        headers['content-type'] = "application/json"

        local data = {
          source = "kong:event_hooks",
          event = "ping",
          operation = operation,
          event_hooks = entity,
        }

        local body, err = cjson.encode(data)
        if err then
          error(err)
        end

        local res, err = request(config.url, {
          method = method,
          body = body,
          sign_with = config.secret and config.secret ~= ngx_null and
                      sign_body(config.secret),
          headers = headers,
          ssl_verify = config.ssl_verify,
        })

        if not err then
          return true, {
            body = res.body,
            headers = res.headers,
            status = res.status
          }
        end

        return nil, err
      end,
    }
  end,

  ["webhook-custom"] = function(entity, config)
    -- Somehow initializing this fails when kong runs on stream only. Something
    -- missing on ngx.location. XXX: check back later
    if not template then
      template = require "resty.template"
    end

    return {
      callback = function(data, event, source, pid)
        local payload, body, headers
        local method = config.method

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

        local res, err = request(config.url, {
          method = method,
          data = payload,
          body = body,
          sign_with = config.secret and config.secret ~= ngx_null and
                      sign_body(config.secret),
          headers = headers,
          ssl_verify = config.ssl_verify,
        })

        if not err then
          return true, {
            body = res.body,
            headers = res.headers,
            status = res.status
          }
        end

        return nil, err
      end,
    }
  end,

  log = function(entity, config)
    return {
      callback = function(data, event, source, pid)
        kong.log.inspect("log callback: ", { event, source, data, pid })

        return true
      end,
    }
  end,

  lambda = function(entity, config)
    local functions = {}

    local opts = { chunk_name = "event_hooks:" .. entity.id }

    local function err_fn(err)
      return function()
        return nil, err
      end
    end

    for i, fn_str in ipairs(config.functions or {}) do
      local fn, err = sandbox.validate_function(fn_str, opts)
      if err then fn = err_fn(err) end

      table.insert(functions, fn)
    end

    return {
      callback = function(data, event, source, pid)
        -- reduce on functions with data
        local err
        for _, fn in ipairs(functions) do
          data, err = fn(data, event, source, pid)
          if err then
            break
          end
        end

        if err then
          return nil, err
        else
          return data
        end
      end,
    }
  end,
}

-- accessors to ease unit testing
_M.events = events
_M.references = references
_M.process_callback = process_callback

return _M
