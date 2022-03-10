local cjson = require "cjson.safe"

local xpcall = xpcall
local type = type
local ipairs = ipairs
local setmetatable = setmetatable
local getmetatable = getmetatable
local next = next
local assert = assert
local tostring = tostring
local traceback = debug.traceback

local ngx = ngx
local log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG


-- creates a new level structure for the callback tree
local new_struct = function()
  return {
    weak_count = 0,
    weak_list = setmetatable({},{ __mode = "v"}),
    strong_count = 0,
    strong_list = {},
    subs = {} -- nested sub tables; source based, and event based
              -- (initial one is global)
  }
end
-- metatable that auto creates sub tables if a key is not found
-- __index function to do the auto table magic
local autotable__index = function(self, key)
  local mt = getmetatable(self)
  local t = new_struct()
  if mt.depth ~= 1 then
    setmetatable(t.subs, {
        __index = mt.__index,
        depth = mt.depth - 1,
    })
  end
  self[key] = t
  return t
end

--- Creates a new auto-table.
-- @param depth (optional, default 1) how deep to auto-generate tables.
-- The last table in the chain generated will itself not be an auto-table.
-- If `depth == 0` then there is no limit.
-- @param mode (optional) set the weak table behavior
-- @return new auto-table
local function autotable(depth)

  local at = new_struct()
  setmetatable(at.subs, {
            __index = autotable__index,
            depth = depth,
          })
  return at
end

-- callbacks
local _callbacks = autotable(2)
-- strong/weak; array = global handlers called on every event
-- strong/weak; hash  = subtables for a specific eventsource
-- eventsource-sub-table has the same structure, except the hash part contains
-- not 'eventsource', but 'event' specific handlers, no more sub tables

local _M = {
  _VERSION = '0.0.1',
}

local function do_handlerlist(handler_list, source, event, data, pid)
  local err, success

  local count_key = "weak_count"
  local list_key = "weak_list"
  while true do
    local i = 1
    local list = handler_list[list_key]
    while i <= handler_list[count_key] do
      local handler = list[i]
      if type(handler) ~= "function" then
        -- handler was removed, unregistered, or GC'ed, cleanup.
        -- Entry is nil, but recreated as a table due to the auto-table
        list[i] = list[handler_list[count_key]]
        list[handler_list[count_key]] = nil
        handler_list[count_key] = handler_list[count_key] - 1
      else
        success, err = xpcall(handler, traceback, data, event, source, pid)
        if not success then
          local d, e
          if type(data) == "table" then
            d, e = cjson.encode(data)
            if not d then d = tostring(e) end
          else
            d = tostring(data)
          end
          log(ERR, "worker-events: event callback failed; source=",source,
                 ", event=", event,", pid=",pid, " error='", tostring(err),
                 "', data=", d)
        end
        i = i + 1
      end
    end
    if list_key == "strong_list" then
      return
    end
    count_key = "strong_count"
    list_key = "strong_list"
  end
end


local function do_event(source, event, data, pid)
  log(DEBUG, "worker-events: handling event; source=",source,
      ", event=", event, ", pid=", pid) --,", data=",tostring(data))
      -- do not log potentially private data, hence skip 'data'

  local list = _callbacks
  do_handlerlist(list, source, event, data, pid)
  list = list.subs[source]
  do_handlerlist(list, source, event, data, pid)
  list = list.subs[event]
  do_handlerlist(list, source, event, data, pid)
end

-- Handle incoming json based event
function _M.do_event_json(json)
  local d, err
  d, err = cjson.decode(json)
  if not d then
    return log(ERR, "worker-events: failed decoding json event data: ", err)
  end

  return do_event(d.source, d.event, d.data, d.pid)
end

-- Handle incoming table based event
function _M.do_event(d)
  return do_event(d.source, d.event, d.data, nil)
end

-- @param mode either "weak" or "strong"
local register = function(callback, mode, source, ...)
  assert(type(callback) == "function", "expected function, got: "..
         type(callback))

  local count_key, list_key
  if mode == "weak" then
    count_key = "weak_count"
    list_key = "weak_list"
  else
    count_key = "strong_count"
    list_key = "strong_list"
  end

  if not source then
    -- register as global event handler
    local list = _callbacks
    local n = list[count_key] + 1
    list[count_key] = n
    list[list_key][n] = callback
  else
    local events = {...}
    if #events == 0 then
      -- register as an eventsource handler
      local list = _callbacks.subs[source]
      local n = list[count_key] + 1
      list[count_key] = n
      list[list_key][n] = callback
    else
      -- register as an event specific handler, for multiple events
      for _, event in ipairs(events) do
        local list = _callbacks.subs[source].subs[event]
        local n = list[count_key] + 1
        list[count_key] = n
        list[list_key][n] = callback
      end
    end
  end
  return true
end


-- registers an event handler callback.
-- signature; callback(source, event, data, originating_pid)
-- @param callback the eventhandler callback to add
-- @param source (optional) if given only this source is being called for
-- @param ... (optional) event names (0 or more) to register for
-- @return true
_M.register = function(callback, source, ...)
  register(callback, "strong", source, ...)
end

-- registers a weak-event handler callback.
-- Workerevents will maintain a weak reference to the handler.
-- signature; callback(source, event, data, originating_pid)
-- @param callback the eventhandler callback to add
-- @param source (optional) if given only this source is being called for
-- @param ... (optional) event names (0 or more) to register for
-- @return true
_M.register_weak = function(callback, source, ...)
  register(callback, "weak", source, ...)
end

-- unregisters an event handler callback.
-- Will remove both the weak and strong references.
-- @param callback the eventhandler callback to remove
-- @return `true` if it was removed, `false` if it was not in the list.
-- If multiple eventnames have been specified, `true` means at least 1
-- occurrence was removed
_M.unregister = function(callback, source, ...)
  assert(type(callback) == "function", "expected function, got: "..
         type(callback))

  local success
  local count_key = "weak_count"
  local list_key = "weak_list"
  -- NOTE: we only set entries to `nil`, the event runner will
  -- cleanup and remove those entries to 'heal' the lists
  while true do
    local list = _callbacks
    if not source then
      -- remove as global event handler
      for i = 1, list[count_key] do
        local cb = list[list_key][i]
        if cb == callback then
          list[list_key][i] = nil
          success = true
        end
      end
    else
      local events = {...}
      if not next(events) then
        -- remove as an eventsource handler
        local target = list.subs[source]
        for i = 1, target[count_key] do
          local cb = target[list_key][i]
          if cb == callback then
            target[list_key][i] = nil
            success = true
          end
        end
      else
        -- remove as an event specific handler, for multiple events
        for _, event in ipairs(events) do
          local target = list.subs[source].subs[event]
          for i = 1, target[count_key] do
            local cb = target[list_key][i]
            if cb == callback then
              target[list_key][i] = nil
              success = true
            end
          end
        end
      end
    end
    if list_key == "strong_list" then
      break
    end
    count_key = "strong_count"
    list_key = "strong_list"
  end

  return (success == true)
end

return _M

