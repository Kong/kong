local cjson = require "cjson.safe"
local semaphore = require "ngx.semaphore"
local callback = require "kong.events.callback"
local client = require("kong.events.protocol").client

local type = type
local str_sub  = string.sub
local table_insert = table.insert
local table_remove = table.remove

local ngx = ngx
local sleep = ngx.sleep
local log = ngx.log
local exiting = ngx.worker.exiting
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG

local spawn = ngx.thread.spawn
local kill = ngx.thread.kill
local wait = ngx.thread.wait

local timer_at = ngx.timer.at
local worker_pid = ngx.worker.pid
--local worker_count = ngx.worker.count

--local _worker_id = ngx.worker.id()
local _worker_pid = worker_pid()
--local _worker_count = worker_count()

local EMPTY_T = {}
local CONNECTION_DELAY = 0.1
local POST_RETRY_DELAY = 0.1

local _M = {
    _VERSION = '0.0.1',
}

local function is_timeout(err)
  return err and str_sub(err, -7) == "timeout"
end

local _configured
local _opts

local _queue
do
  local queue_semaphore = semaphore.new()

  _queue = {
    wait = function(...)
      return queue_semaphore:wait(...)
    end,
    post = function(...)
      return queue_semaphore:post(...)
    end
  }
end

local communicate

communicate = function(premature)
  if premature then
    -- worker wants to exit
    return
  end

  local conn = assert(client:new())

  local ok, err = conn:connect(_opts.listening)
  if not ok then
    log(DEBUG, "failed to connect: ", err)

    -- try to reconnect broker
    assert(timer_at(CONNECTION_DELAY, function(premature)
      communicate(premature)
    end))

    return
  end

  _configured = true

  local read_thread = spawn(function()
    while not exiting() do
      local data, err = conn:recv_frame()

      if exiting() then
        return
      end

      if err then
        if not is_timeout(err) then
          return nil, err
        end

        -- timeout
        goto continue
      end

      if not data then
        return nil, "did not receive frame from broker"
      end

      -- got an event data, callback
      callback.run(data)

      ::continue::
    end -- while not exiting
  end)  -- read_thread

  local write_thread = spawn(function()
    while not exiting() do
      local ok, err = _queue.wait(5)

      if exiting() then
        return
      end

      if not ok then
        if not is_timeout(err) then
          return nil, "semaphore wait error: " .. err
        end

        -- timeout
        goto continue
      end

      local payload = table_remove(_queue, 1)
      if not payload then
        return nil, "queue can not be empty after semaphore returns"
      end

      local _, err = conn:send_frame(payload)
      if err then
        log(ERR, "failed to send: ", err)

        -- try to post it again
        sleep(POST_RETRY_DELAY)

        table_insert(_queue, payload)
        _queue:post()
      end

      ::continue::
    end -- while not exiting
  end)  -- write_thread

  local ok, err, perr = wait(write_thread, read_thread)

  kill(write_thread)
  kill(read_thread)

  _configured = nil

  if not ok then
    log(ERR, "event client failed: ", err)
  end

  if perr then
    log(ERR, "event client failed: ", perr)
  end

  if not exiting() then
    assert(timer_at(CONNECTION_DELAY, function(premature)
      communicate(premature)
    end))
  end
end

function _M.configure(opts)
  assert(type(opts) == "table", "Expected a table, got "..type(opts))

  _opts = opts

  assert(timer_at(0, function(premature)
    communicate(premature)
  end))

  return true
end

-- posts a new event
local function post_event(source, event, data, typ)
  if not _configured then
    return nil, "not initialized yet"
  end

  if type(source) ~= "string" or source == "" then
    return nil, "source is required"
  end

  if type(event) ~= "string" or event == "" then
    return nil, "event is required"
  end

  local json, err

  -- encode event info
  json, err = cjson.encode({
    source = source,
    event = event,
    data = data,
    pid = _worker_pid,
  })

  if not json then
    return nil, err
  end

  -- encode typ info
  json, err = cjson.encode({
    typ = typ or EMPTY_T,
    data = json,
  })

  if not json then
    return nil, err
  end

  table_insert(_queue, json)

  _queue:post()

  return true
end

function _M.post(source, event, data, unique)
  local ok, err = post_event(source, event, data, {["unique"] = unique})
  if not ok then
    log(ERR, "post event: ", err)
    return nil, err
  end

  return true
end

function _M.post_local(source, event, data)
  local ok, err = post_event(source, event, data, {["local"] = true})
  if not ok then
    log(ERR, "post event: ", err)
    return nil, err
  end

  return true
end

-- compatible for lua-resty-worker-events
function _M.poll()
end

_M.register = callback.register
_M.register_weak = callback.register_weak
_M.unregister = callback.unregister

return _M
