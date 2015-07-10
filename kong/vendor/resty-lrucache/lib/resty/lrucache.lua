-- Copyright (C) Yichun Zhang (agentzh)


local ffi = require "ffi"
local ffi_new = ffi.new
local ffi_sizeof = ffi.sizeof
local ffi_cast = ffi.cast
local ffi_fill = ffi.fill
local ngx_now = ngx.now
local uintptr_t = ffi.typeof("uintptr_t")
local setmetatable = setmetatable
local tonumber = tonumber


-- queue data types
--
-- this queue is a double-ended queue and the first node
-- is reserved for the queue itself.
-- the implementation is mostly borrowed from nginx's ngx_queue_t data
-- structure.

ffi.cdef[[
    typedef struct lrucache_queue_s  lrucache_queue_t;
    struct lrucache_queue_s {
        double             expire;  /* in seconds */
        lrucache_queue_t  *prev;
        lrucache_queue_t  *next;
    };
]]

local queue_arr_type = ffi.typeof("lrucache_queue_t[?]")
local queue_ptr_type = ffi.typeof("lrucache_queue_t*")
local queue_type = ffi.typeof("lrucache_queue_t")
local NULL = ffi.null


-- queue utility functions

local function queue_insert_tail(h, x)
    local last = h[0].prev
    x.prev = last
    last.next = x
    x.next = h
    h[0].prev = x
end


local function queue_init(size)
    if not size then
        size = 0
    end
    local q = ffi_new(queue_arr_type, size + 1)
    ffi_fill(q, ffi_sizeof(queue_type, size + 1), 0)

    if size == 0 then
        q[0].prev = q
        q[0].next = q

    else
        local prev = q[0]
        for i = 1, size do
          local e = q[i]
          prev.next = e
          e.prev = prev
          prev = e
        end

        local last = q[size]
        last.next = q
        q[0].prev = last
    end

    return q
end


local function queue_is_empty(q)
    -- print("q: ", tostring(q), "q.prev: ", tostring(q), ": ", q == q.prev)
    return q == q[0].prev
end


local function queue_remove(x)
    local prev = x.prev
    local next = x.next

    next.prev = prev
    prev.next = next

    -- for debugging purpose only:
    x.prev = NULL
    x.next = NULL
end


local function queue_insert_head(h, x)
    x.next = h[0].next
    x.next.prev = x
    x.prev = h
    h[0].next = x
end


local function queue_last(h)
    return h[0].prev
end


local function queue_head(h)
    return h[0].next
end


-- true module stuffs

local _M = {
    _VERSION = '0.04'
}
local mt = { __index = _M }


local function ptr2num(ptr)
    return tonumber(ffi_cast(uintptr_t, ptr))
end


function _M.new(size)
    if size < 1 then
        return nil, "size too small"
    end

    local self = {
        keys = {},
        hasht = {},
        free_queue = queue_init(size),
        cache_queue = queue_init(),
        key2node = {},
        node2key = {},
    }
    return setmetatable(self, mt)
end


function _M.get(self, key)
    local hasht = self.hasht
    local val = hasht[key]
    if not val then
        return nil
    end

    local node = self.key2node[key]

    -- print(key, ": moving node ", tostring(node), " to cache queue head")
    local cache_queue = self.cache_queue
    queue_remove(node)
    queue_insert_head(cache_queue, node)

    if node.expire >= 0 and node.expire < ngx_now() then
        -- print("expired: ", node.expire, " > ", ngx_now())
        return nil, val
    end
    return val
end


function _M.delete(self, key)
    self.hasht[key] = nil

    local key2node = self.key2node
    local node = key2node[key]

    if not node then
        return false
    end

    key2node[key] = nil
    self.node2key[ptr2num(node)] = nil

    queue_remove(node)
    queue_insert_tail(self.free_queue, node)
    return true
end


function _M.set(self, key, value, ttl)
    local hasht = self.hasht
    hasht[key] = value

    local key2node = self.key2node
    local node = key2node[key]
    if not node then
        local free_queue = self.free_queue
        local node2key = self.node2key

        if queue_is_empty(free_queue) then
            -- evict the least recently used key
            -- assert(not queue_is_empty(self.cache_queue))
            node = queue_last(self.cache_queue)

            local oldkey = node2key[ptr2num(node)]
            -- print(key, ": evicting oldkey: ", oldkey, ", oldnode: ",
            --         tostring(node))
            if oldkey then
                hasht[oldkey] = nil
                key2node[oldkey] = nil
            end

        else
            -- take a free queue node
            node = queue_head(free_queue)
            -- print(key, ": get a new free node: ", tostring(node))
        end

        node2key[ptr2num(node)] = key
        key2node[key] = node
    end

    queue_remove(node)
    queue_insert_head(self.cache_queue, node)

    if ttl then
        node.expire = ngx_now() + ttl
    else
        node.expire = -1
    end
end


return _M
