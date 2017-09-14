-- vim: st=4 sts=4 sw=4 et:

local cjson      = require "cjson.safe"
local lrucache   = require "resty.lrucache"
local resty_lock = require "resty.lock"


local now          = ngx.now
local fmt          = string.format
local sub          = string.sub
local find         = string.find
local huge         = math.huge
local type         = type
local pcall        = pcall
local error        = error
local shared       = ngx.shared
local tostring     = tostring
local tonumber     = tonumber
local setmetatable = setmetatable


local LOCK_KEY_PREFIX         = "lua-resty-mlcache:lock:"
local CACHE_MISS_SENTINEL_LRU = {}


local TYPES_LOOKUP = {
    number  = 1,
    boolean = 2,
    string  = 3,
    table   = 4,
}


local marshallers = {
    shm_value = function(str_value, value_type, at, ttl)
        return fmt("%d:%f:%f:%s", value_type, at, ttl, str_value)
    end,

    shm_nil = function(at, ttl)
        return fmt("0:%f:%f:", at, ttl)
    end,

    [1] = function(number) -- number
        return tostring(number)
    end,

    [2] = function(bool)   -- boolean
        return bool and "true" or "false"
    end,

    [3] = function(str)    -- string
        return str
    end,

    [4] = function(t)      -- table
        local json, err = cjson.encode(t)
        if not json then
            return nil, "could not encode table value: " .. err
        end

        return json
    end,
}


local unmarshallers = {
    shm_value = function(marshalled)
        -- split our shm marshalled value by the hard-coded ":" tokens
        -- "type:at:ttl:value"
        local ttl_last = find(marshalled, ":", 21, true) - 1

        local value_type = sub(marshalled, 1, 1)
        local at         = sub(marshalled, 3, 19)
        local ttl        = sub(marshalled, 21, ttl_last)
        local str_value  = sub(marshalled, ttl_last + 2)

        return str_value, tonumber(value_type), tonumber(at), tonumber(ttl)
    end,

    [1] = function(str) -- number
        return tonumber(str)
    end,

    [2] = function(str) -- boolean
        return str == "true"
    end,

    [3] = function(str) -- string
        return str
    end,

    [4] = function(str) -- table
        local t, err = cjson.decode(str)
        if not t then
            return nil, "could not decode table value: " .. err
        end

        return t
    end,
}


local _M = {}
local mt = { __index = _M }


function _M.new(shm, ipc, opts)
    if type(shm) ~= "string" then
        return error("shm must be a string")
    end

    if not ipc then
        return error("ipc must be given")
    end

    if opts then
        if type(opts) ~= "table" then
            return error("opts must be a table")
        end

        if opts.lru_size and type(opts.lru_size) ~= "number" then
            return error("opts.lru_size must be a number")
        end

        if opts.ttl then
            if type(opts.ttl) ~= "number" then
                return error("opts.ttl must be a number")
            end

            if opts.ttl < 0 then
                return error("opts.ttl must be >= 0")
            end
        end

        if opts.neg_ttl then
            if type(opts.neg_ttl) ~= "number" then
                return error("opts.neg_ttl must be a number")
            end

            if opts.neg_ttl < 0 then
                return error("opts.neg_ttl must be >= 0")
            end
        end

        if opts.resty_lock_opts and type(opts.resty_lock_opts) ~= "table" then
            return error("opts.resty_lock_opts must be a table")
        end

    else
        opts = {}
    end

    local dict = shared[shm]
    if not dict then
        return nil, "no such lua_shared_dict: " .. shm
    end

    local lru_size = opts.lru_size or 100

    local self          = {
        lru_size        = lru_size,
        lru             = lrucache.new(lru_size),
        dict            = dict,
        shm             = shm,
        ttl             = opts.ttl     or 30,
        neg_ttl         = opts.neg_ttl or 5,
        resty_lock_opts = opts.resty_lock_opts,
    }

    ipc.register(function(data)
        local key = data

        self.lru:delete(key)
    end, "mlcache", "invalidations")

    ipc.register(function()
        self.lru = lrucache.new(self.lru_size)
    end, "mlcache", "purge")

    self.ipc = ipc

    return setmetatable(self, mt)
end


function _M:purge(flush_expired)
    self.dict:flush_all()

    if flush_expired then
        self.dict:flush_expired()
    end

    self.lru = lrucache.new(self.lru_size)

    local ok, err = self.ipc.post("mlcache", "purge")
    if not ok then
        return nil, "could not post IPC purge event: " .. err
    end

    return true
end


local function set_lru(self, key, value, ttl)
    if ttl == 0 then
        ttl = huge
    end

    self.lru:set(key, value, ttl)

    return value
end


local function shmlru_get(self, key)
    local v, err = self.dict:get(key)
    if err then
        return nil, "could not read from lua_shared_dict: " .. err
    end

    if v ~= nil then
        local str_serialized, value_type, at, ttl = unmarshallers.shm_value(v)

        local remaining_ttl = ttl - (now() - at)

        -- value_type of 0 is a nil entry
        if value_type == 0 then
            return set_lru(self, key, CACHE_MISS_SENTINEL_LRU, remaining_ttl)
        end

        local value, err = unmarshallers[value_type](str_serialized)
        if err then
            return nil, "could not deserialize value after lua_shared_dict " ..
                        "retrieval: " .. err
        end

        return set_lru(self, key, value, remaining_ttl)
    end
end


local function shmlru_set(self, key, value, ttl, neg_ttl)
    local at = now()

    if value == nil then
        local shm_nil = marshallers.shm_nil(at, neg_ttl)

        -- we need to cache that this was a miss, and ensure cache hit for a
        -- nil value
        local ok, err = self.dict:set(key, shm_nil, neg_ttl)
        if not ok then
            return nil, "could not write to lua_shared_dict: " .. err
        end

        -- set our own worker's LRU cache

        set_lru(self, key, CACHE_MISS_SENTINEL_LRU, neg_ttl)

        return nil
    end

    -- serialize insertion time + Lua types for shm storage

    local value_type = TYPES_LOOKUP[type(value)]

    if not marshallers[value_type] then
        return error("cannot cache value of type " .. type(value))
    end

    local str_marshalled, err = marshallers[value_type](value)
    if not str_marshalled then
        return nil, "could not serialize value for lua_shared_dict insertion: "
                    .. err
    end

    local shm_marshalled = marshallers.shm_value(str_marshalled, value_type,
                                                 at, ttl)

    -- cache value in shm for currently-locked workers

    local ok, err = self.dict:set(key, shm_marshalled, ttl)
    if not ok then
        return nil, "could not write to lua_shared_dict: " .. err
    end

    -- set our own worker's LRU cache

    return set_lru(self, key, value, ttl)
end


local function unlock_and_ret(lock, res, err)
    local ok, lerr = lock:unlock()
    if not ok then
        return nil, "could not unlock callback: " .. lerr
    end

    return res, err
end


function _M:get(key, opts, cb, ...)
    if type(key) ~= "string" then
        return error("key must be a string")
    end

    if type(cb) ~= "function" then
        return error("callback must be a function")
    end

    -- opts validation

    local ttl
    local neg_ttl

    if opts then
        if type(opts) ~= "table" then
            return error("opts must be a table")
        end

        if opts.ttl then
            if type(opts.ttl) ~= "number" then
                return error("opts.ttl must be a number")
            end

            if opts.ttl < 0 then
                return error("opts.ttl must be >= 0")
            end
        end

        if opts.neg_ttl then
            if type(opts.neg_ttl) ~= "number" then
                return error("opts.neg_ttl must be a number")
            end

            if opts.neg_ttl < 0 then
                return error("opts.neg_ttl must be >= 0")
            end
        end

        ttl     = opts.ttl
        neg_ttl = opts.neg_ttl
    end

    if not ttl then
        ttl = self.ttl
    end

    if not neg_ttl then
        neg_ttl = self.neg_ttl
    end

    -- worker LRU cache retrieval

    local data = self.lru:get(key)
    if data == CACHE_MISS_SENTINEL_LRU then
        return nil
    end

    if data ~= nil then
        return data
    end

    -- not in worker's LRU cache, need shm lookup

    local err
    data, err = shmlru_get(self, key)
    if err then
        return nil, err
    end

    if data == CACHE_MISS_SENTINEL_LRU then
        return nil
    end

    if data ~= nil then
        return data
    end

    -- not in shm either
    -- single worker must execute the callback

    local lock, err = resty_lock:new(self.shm, self.resty_lock_opts)
    if not lock then
        return nil, "could not create lock: " .. err
    end

    local elapsed, err = lock:lock(LOCK_KEY_PREFIX .. key)
    if not elapsed then
        return nil, "could not aquire callback lock: " .. err
    end

    -- check for another worker's success at running the callback

    data, err = shmlru_get(self, key)
    if err then
        return unlock_and_ret(lock, nil, err)
    end

    if data then
        if data == CACHE_MISS_SENTINEL_LRU then
            return unlock_and_ret(lock, nil)
        end

        return unlock_and_ret(lock, data)
    end

    -- still not in shm, we are responsible for running the callback

    local ok, err = pcall(cb, ...)
    if not ok then
        return unlock_and_ret(lock, nil, "callback threw an error: " .. err)
    end

    local value, err = shmlru_set(self, key, err, ttl, neg_ttl)
    if err then
        return unlock_and_ret(lock, nil, err)
    end

    return unlock_and_ret(lock, value)
end


function _M:probe(key)
    if type(key) ~= "string" then
        return error("key must be a string")
    end

    local v, err = self.dict:get(key)
    if err then
        return nil, "could not read from lua_shared_dict: " .. err
    end

    if v ~= nil then
        local str_serialized, value_type, at, ttl = unmarshallers.shm_value(v)

        local remaining_ttl = ttl - (now() - at)

        -- value_type of 0 is a nil entry
        if value_type == 0 then
            return remaining_ttl
        end

        local value, err = unmarshallers[value_type](str_serialized)
        if err then
            return nil, "could not deserialize value after lua_shared_dict " ..
                        "retrieval: " .. err
        end

        return remaining_ttl, nil, value
    end
end


function _M:delete(key)
    if type(key) ~= "string" then
        return error("key must be a string")
    end

    self.lru:delete(key)

    local ok, err = self.dict:delete(key)
    if not ok then
        return nil, "could not delete from shm: " .. err
    end

    local _, err = self.ipc.post("mlcache", "invalidations", key)
    if err then
        return nil, "could not post IPC invalidation event: " .. err
    end

    return true
end


return _M
