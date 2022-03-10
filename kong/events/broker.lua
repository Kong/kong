local cjson = require "cjson.safe"
local lrucache = require "resty.lrucache"
local semaphore = require "ngx.semaphore"
local server = require("kong.events.protocol").server
local kong_sock = require "resty.kong.socket"

local type = type
local pairs = pairs
local setmetatable = setmetatable
local str_sub  = string.sub
local table_insert = table.insert
local table_remove = table.remove
--local random = math.random

local ngx = ngx
local log = ngx.log
local exit = ngx.exit
local exiting = ngx.worker.exiting
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG

local spawn = ngx.thread.spawn
local kill = ngx.thread.kill
local wait = ngx.thread.wait

--local worker_pid = ngx.worker.pid
--local worker_count = ngx.worker.count

local _worker_id = ngx.worker.id()
--local _worker_pid = worker_pid()
--local _worker_count = worker_count()

local DEFAULT_UNIQUE_TIMEOUT = 5
local MAX_UNIQUE_EVENTS = 1024

local _opts

local _clients = setmetatable({}, { __mode = "k", })

local _uniques, err = lrucache.new(MAX_UNIQUE_EVENTS)
if not _uniques then
  error("failed to create the events cache: " .. (err or "unknown"))
end

local _M = {
    _VERSION = '0.0.1',
}
--local mt = { __index = _M, }

local function is_timeout(err)
  return err and str_sub(err, -7) == "timeout"
end

-- opts = {server_id = n, listening = 'unix:...', timeout = n,}
function _M.configure(opts)
  assert(type(opts) == "table", "Expected a table, got "..type(opts))

  -- only enable listening on special worker id
  if _worker_id ~= opts.server_id then
      kong_sock.close_listening(opts.listening)
      return
  end

  _opts = opts

  return true
end

function _M.run()
  local conn, err = server:new()

  if not conn then
      log(ERR, "failed to init socket: ", err)
      exit(444)
  end

  local queue
  do
    local queue_semaphore = semaphore.new()

    queue = {
      wait = function(...)
        return queue_semaphore:wait(...)
      end,
      post = function(...)
        return queue_semaphore:post(...)
      end
    }
  end

  _clients[conn] = queue

  local read_thread = spawn(function()
    while not exiting() do
      local data, err = conn:recv_frame()

      if exiting() then
        -- try to close ASAP
        kong_sock.close_listening(_opts.listening)
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
        return nil, "did not receive frame from client"
      end

      local d, err

      d, err = cjson.decode(data)
      if not d then
        log(ERR, "worker-events: failed decoding json event data: ", err)
        goto continue
      end

      local typ = d.typ

      -- local event, send back
      if typ["local"] == true then
        table_insert(queue, d.data)
        queue.post()

        goto continue
      end

      -- unique event
      local unique = typ["unique"]
      if unique then
        if _uniques:get(unique) then
          --log(DEBUG, "unique event is duplicate: ", unique)
          goto continue
        end

        _uniques:set(unique, 1, _opts.timeout or DEFAULT_UNIQUE_TIMEOUT)
      end

      -- broadcast to all/unique workers
      local n = 0
      for _, q in pairs(_clients) do
        table_insert(q, d.data)
        q.post()
        n = n + 1

        if unique then
          break
        end
      end

      log(DEBUG, "event published to ", n, " workers")

      ::continue::
    end -- while not exiting
  end)  -- read_thread

  local write_thread = spawn(function()
    while not exiting() do
      local ok, err = queue.wait(5)

      if exiting() then
        return
      end

      if not ok then
        if not is_timeout(err) then
          return nil, "semaphore wait error: " .. err
        end

        -- timeout, send ping?
        goto continue
      end

      local payload = table_remove(queue, 1)
      if not payload then
        return nil, "queue can not be empty after semaphore returns"
      end

      local _, err = conn:send_frame(payload)
      if err then
          log(ERR, "failed to send: ", err)
      end

      ::continue::
    end -- while not exiting
  end)  -- write_thread

  local ok, err, perr = wait(write_thread, read_thread)

  _clients[conn] = nil

  kill(write_thread)
  kill(read_thread)

  if not ok then
    log(ERR, "event broker failed: ", err)
    return exit(ngx.ERROR)
  end

  if perr then
    log(ERR, "event broker failed: ", err)
    return exit(ngx.ERROR)
  end

  return exit(ngx.OK)
end

return _M

