-- vim: ts=4 sts=4 sw=4 et:

local ERR          = ngx.ERR
local WARN         = ngx.WARN
local INFO         = ngx.INFO
local sleep        = ngx.sleep
local shared       = ngx.shared
local worker_pid   = ngx.worker.pid
local ngx_log      = ngx.log
local fmt          = string.format
local sub          = string.sub
local find         = string.find
local min          = math.min
local type         = type
local pcall        = pcall
local error        = error
local insert       = table.insert
local tonumber     = tonumber
local setmetatable = setmetatable


local INDEX_KEY        = "lua-resty-ipc:index"
local FORCIBLE_KEY     = "lua-resty-ipc:forcible"
local POLL_SLEEP_RATIO = 2


local function marshall(worker_pid, channel, data)
    return fmt("%d:%d:%s%s", worker_pid, #data, channel, data)
end


local function unmarshall(str)
    local sep_1 = find(str, ":", nil      , true)
    local sep_2 = find(str, ":", sep_1 + 1, true)

    local pid      = tonumber(sub(str, 1        , sep_1 - 1))
    local data_len = tonumber(sub(str, sep_1 + 1, sep_2 - 1))

    local channel_last_pos = #str - data_len

    local channel = sub(str, sep_2 + 1, channel_last_pos)
    local data    = sub(str, channel_last_pos + 1)

    return pid, channel, data
end


local function log(lvl, ...)
    return ngx_log(lvl, "[ipc] ", ...)
end


local _M = {}
local mt = { __index = _M }


function _M.new(shm, debug)
    local dict = shared[shm]
    if not dict then
        return nil, "no such lua_shared_dict: " .. shm
    end

    local self    = {
        dict      = dict,
        pid       = debug and 0 or worker_pid(),
        idx       = 0,
        callbacks = {},
    }

    return setmetatable(self, mt)
end


function _M:subscribe(channel, cb)
    if type(channel) ~= "string" then
        error("channel must be a string", 2)
    end

    if type(cb) ~= "function" then
        error("callback must be a function", 2)
    end

    if not self.callbacks[channel] then
        self.callbacks[channel] = { cb }

    else
        insert(self.callbacks[channel], cb)
    end
end


function _M:broadcast(channel, data)
    if type(channel) ~= "string" then
        error("channel must be a string", 2)
    end

    if type(data) ~= "string" then
        error("data must be a string", 2)
    end

    local marshalled_event = marshall(worker_pid(), channel, data)

    local idx, err = self.dict:incr(INDEX_KEY, 1, 0)
    if not idx then
        return nil, "failed to increment index: " .. err
    end

    local ok, err, forcible = self.dict:set(idx, marshalled_event)
    if not ok then
        return nil, "failed to insert event in shm: " .. err
    end

    if forcible then
        -- take note that eviction has started
        -- we repeat this flagging to avoid this key from ever being
        -- evicted itself
        local ok, err = self.dict:set(FORCIBLE_KEY, true)
        if not ok then
            return nil, "failed to set forcible flag in shm: " .. err
        end
    end

    return true
end


-- Note: if this module were to be used by users (that is, users can implement
-- their own pub/sub events and thus, callbacks), this method would then need
-- to consider the time spent in callbacks to prevent long running callbacks
-- from penalizing the worker.
-- Since this module is currently only used by mlcache, whose callback is an
-- shm operation, we only worry about the time spent waiting for events
-- between the 'incr()' and 'set()' race condition.
function _M:poll(timeout)
    if timeout ~= nil and type(timeout) ~= "number" then
        error("timeout must be a number", 2)
    end

    local shm_idx, err = self.dict:get(INDEX_KEY)
    if err then
        return nil, "failed to get index: " .. err
    end

    if shm_idx == nil then
        -- no events to poll yet
        return true
    end

    if type(shm_idx) ~= "number" then
        return nil, "index is not a number, shm tampered with"
    end

    if not timeout then
        timeout = 0.3
    end

    if self.idx == 0 then
        local forcible, err = self.dict:get(FORCIBLE_KEY)
        if err then
            return nil, "failed to get forcible flag from shm: " .. err
        end

        if forcible then
            -- shm lru eviction occurred, we are likely a new worker
            -- skip indexes that may have been evicted and resume current
            -- polling idx
            self.idx = shm_idx - 1
        end

    else
        -- guard: self.idx <= shm_idx
        self.idx = min(self.idx, shm_idx)
    end

    local elapsed = 0

    for _ = self.idx, shm_idx - 1 do
        -- fetch event from shm with a retry policy in case
        -- we run our :get() in between another worker's
        -- :incr() and :set()

        local v
        local idx = self.idx + 1

        do
            local perr
            local pok        = true
            local sleep_step = 0.001

            while elapsed < timeout do
                v, err = self.dict:get(idx)
                if v ~= nil or err then
                    break
                end

                if pok then
                    log(INFO, "no event data at index '", idx, "', ",
                              "retrying in: ", sleep_step, "s")

                    -- sleep is not available in all ngx_lua contexts
                    -- if we fail once, never retry to sleep
                    pok, perr = pcall(sleep, sleep_step)
                    if not pok then
                        log(WARN, "could not sleep before retry: ", perr,
                                  " (note: it is safer to call this function ",
                                  "in contexts that support the ngx.sleep() ",
                                  "API)")
                    end
                end

                elapsed    = elapsed + sleep_step
                sleep_step = min(sleep_step * POLL_SLEEP_RATIO,
                                 timeout - elapsed)
            end
        end

        -- fetch next event on next iteration
        -- even if we timeout, we might miss 1 event (we return in timeout and
        -- we don't retry that event), but it's better than being stuck forever
        -- on an event that might have been evicted from the shm.
        self.idx = idx

        if elapsed >= timeout then
            return nil, "timeout"
        end

        if err then
            log(ERR, "could not get event at index '", self.idx, "': ", err)

        elseif type(v) ~= "string" then
            log(ERR, "event at index '", self.idx, "' is not a string, ",
                     "shm tampered with")

        else
            local pid, channel, data = unmarshall(v)

            if self.pid ~= pid then
                -- coming from another worker
                local cbs = self.callbacks[channel]
                if cbs then
                    for j = 1, #cbs do
                        local pok, perr = pcall(cbs[j], data)
                        if not pok then
                            log(ERR, "callback for channel '", channel,
                                     "' threw a Lua error: ", perr)
                        end
                    end
                end
            end
        end
    end

    return true
end


return _M
