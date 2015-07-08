-- Copyright (C) Yichun Zhang (agentzh)
-- Copyright (C) Shuxin Yang

--[[
  This module implements a key/value cache store. We adopt LRU as our
replace/evict policy. Each key/value pair is tagged with a Time-to-Live (TTL);
from user's perspective, stale pairs are automatically removed from the cache.

Why FFI
-------
  In Lua, expression "table[key] = nil" does not *PHYSICALLY* remove the value
associated with the key; it just set the value to be nil! So the table will
keep growing with large number of the key/nil pairs which will be purged until
resize() operator is called.

  This "feature" is terribly ill-suited to what we need. Therefore we have to
rely on FFI to build a hash-table where any entry can be physically deleted
immediately.

Under the hood:
--------------
  In concept, we introduce three data structures to implement the cache store:
    1. key/value vector for storing keys and values.
    2. a queue to mimic the LRU.
    3. hash-table for looking up the value for a given key.

  Unfortunately, efficiency and clarity usually come at each other cost. The
data strucutres we are using are slightly more complicated than what we
described above.

   o. Lua does not have efficient way to store a vector of pair. So, we use
      two vectors for key/value pair: one for keys and the other for values
      (_M.key_v and _M.val_v, respectively), and i-th key corresponds to
      i-th value.

      A key/value pair is identified by the "id" field in a "node" (we shall
      discuss node later)

    o. The queue is nothing more than a doubly-linked list of "node" linked via
        lrucache_pureffi_queue_s::{next|prev} fields.

    o. The hash-table has two parts:
        - the _M.bucket_v[] a vector of bucket, indiced by hash-value, and
        - a bucket is a singly-linked list of "node" via the
          lrucache_pureffi_queue_s::conflict field.

      A key must be a string, and the hash value of a key is evaluated by:
      crc32(key-cast-to-pointer) % size(_M.bucket_v).
      We mandate size(_M.bucket_v) being a power-of-two in order to avoid
      expensive modulo operation.

    At the heart of the module is an array of "node" (of type
    lrucache_pureffi_queue_s). A node:
      - keeps the meta-data of its corresponding key/value pair
        (embodied by the "id", and "expire" field);
      - is a part of LRU queue (embodied by "prev" and "next" fields);
      - is a part of hash-table (embodied by the "conflict" field).
]]

local ffi = require "ffi"
local bit = require "bit"


local ffi_new = ffi.new
local ffi_sizeof = ffi.sizeof
local ffi_cast = ffi.cast
local ffi_fill = ffi.fill
local ngx_now = ngx.now
local uintptr_t = ffi.typeof("uintptr_t")
local c_str_t = ffi.typeof("const char*")
local int_t = ffi.typeof("int")
local int_array_t = ffi.typeof("int[?]")


local crc_tab = ffi.new("const unsigned int[256]", {
    0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F,
    0xE963A535, 0x9E6495A3, 0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988,
    0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91, 0x1DB71064, 0x6AB020F2,
    0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
    0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9,
    0xFA0F3D63, 0x8D080DF5, 0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172,
    0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B, 0x35B5A8FA, 0x42B2986C,
    0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
    0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423,
    0xCFBA9599, 0xB8BDA50F, 0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924,
    0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D, 0x76DC4190, 0x01DB7106,
    0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
    0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D,
    0x91646C97, 0xE6635C01, 0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E,
    0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457, 0x65B0D9C6, 0x12B7E950,
    0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
    0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7,
    0xA4D1C46D, 0xD3D6F4FB, 0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0,
    0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9, 0x5005713C, 0x270241AA,
    0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
    0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81,
    0xB7BD5C3B, 0xC0BA6CAD, 0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A,
    0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683, 0xE3630B12, 0x94643B84,
    0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
    0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB,
    0x196C3671, 0x6E6B06E7, 0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC,
    0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5, 0xD6D6A3E8, 0xA1D1937E,
    0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
    0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55,
    0x316E8EEF, 0x4669BE79, 0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236,
    0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F, 0xC5BA3BBE, 0xB2BD0B28,
    0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
    0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F,
    0x72076785, 0x05005713, 0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38,
    0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21, 0x86D3D2D4, 0xF1D4E242,
    0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
    0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69,
    0x616BFFD3, 0x166CCF45, 0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2,
    0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB, 0xAED16A4A, 0xD9D65ADC,
    0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
    0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693,
    0x54DE5729, 0x23D967BF, 0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94,
    0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D });

local setmetatable = setmetatable
local tonumber = tonumber

local brshift = bit.rshift
local bxor = bit.bxor
local band = bit.band

local ok, tab_new = pcall(require, "table.new")
if not ok then
    tab_new = function (narr, nrec) return {} end
end

-- queue data types
--
-- this queue is a double-ended queue and the first node
-- is reserved for the queue itself.
-- the implementation is mostly borrowed from nginx's ngx_queue_t data
-- structure.

ffi.cdef[[
    /* A lrucache_pureffi_queue_s node hook together three data structures:
     *   o. the key/value store as embodied by the "id" (which is in essence the
     *      indentifier of key/pair pair) and the "expire" (which is a metadata
     *      of the corresponding key/pair pair).
     *   o. The LRU queue via the prev/next fields.
     *   o. The hash-tabble as embodied by the "conflict" field.
     */
    typedef struct lrucache_pureffi_queue_s  lrucache_pureffi_queue_t;
    struct lrucache_pureffi_queue_s {
        /* Each node is assigned a unique ID at construction time, and the
         * ID remain immutatble, regardless the node is in active-list or
         * free-list. The queue header is assigned ID 0. Since queue-header
         * is a sentinel node, 0 denodes "invalid ID".
         *
         * Intuitively, we can view the "id" as the identifier of key/value
         * pair.
         */
        int                id;

        /* The bucket of the hash-table is implemented as a singly-linked list.
         * The "conflict" refers to the ID of the next node in the bucket.
         */
        int                conflict;

        double             expire;  /* in seconds */

        lrucache_pureffi_queue_t  *prev;
        lrucache_pureffi_queue_t  *next;
    };
]]

local queue_arr_type = ffi.typeof("lrucache_pureffi_queue_t[?]")
local queue_ptr_type = ffi.typeof("lrucache_pureffi_queue_t*")
local queue_type = ffi.typeof("lrucache_pureffi_queue_t")
local NULL = ffi.null


--========================================================================
--
--              Queue utility functions
--
--========================================================================

-- Append the element "x" to the given queue "h".
local function queue_insert_tail(h, x)
    local last = h[0].prev
    x.prev = last
    last.next = x
    x.next = h
    h[0].prev = x
end


--[[
Allocate a queue with size + 1 elements. Elements are linked together in a
circular way, i.e. the last element's "next" points to the first element,
while the first element's "prev" element points to the last element.
]]
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
          e.id = i
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


-- Insert the element "x" the to the given queue "h"
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


--========================================================================
--
--              Miscellaneous Utility Functions
--
--========================================================================

local function ptr2num(ptr)
    return tonumber(ffi_cast(uintptr_t, ptr))
end


local function crc32_ptr(ptr)
    local crc32 = 0;

    local p = brshift(ptr2num(ptr), 3)
    local b = band(p, 255)
    crc32 = crc_tab[b]

    b = band(brshift(p, 8), 255)
    crc32 = bxor(brshift(crc32, 8), crc_tab[band(bxor(crc32, b), 255)])

    b = band(brshift(p, 16), 255)
    crc32 = bxor(brshift(crc32, 8), crc_tab[band(bxor(crc32, b), 255)])

    --b = band(brshift(p, 24), 255)
    --crc32 = bxor(brshift(crc32, 8), crc_tab[band(bxor(crc32, b), 255)])
    return crc32
end


--========================================================================
--
--              Implementation of "export" functions
--
--========================================================================

local _M = {
    _VERSION = '0.04'
}
local mt = { __index = _M }


-- "size" specifies the maximum number of entries in the LRU queue, and the
-- "load_factor" designates the 'load factor' of the hash-table we are using
-- internally. The default value of load-factor is 0.5 (i.e. 50%); if the
-- load-factor is specified, it will be clamped to the range of [0.1, 1](i.e.
-- if load-factor is greater than 1, it will be saturated to 1, likewise,
-- if load-factor is smaller than 0.1, it will be clamped to 0.1).
function _M.new(size, load_factor)
    if size < 1 then
        return nil, "size too small"
    end

    -- Determine bucket size, which must be power of two.
    local load_f = load_factor
    if not load_factor then
        load_f = 0.5
    elseif load_factor > 1 then
        load_f = 1
    elseif load_factor < 0.1 then
        load_f = 0.1
    end

    local bs_min = size / load_f
    -- The bucket_sz *MUST* be a power-of-two. See the hash_string().
    local bucket_sz = 1
    repeat
        bucket_sz = bucket_sz * 2
    until bucket_sz >= bs_min

    local self = {
        size = size,
        bucket_sz = bucket_sz,
        free_queue = queue_init(size),
        cache_queue = queue_init(0),
        node_v = nil,
        key_v = tab_new(size, 0),
        val_v = tab_new(size, 0),
        bucket_v = ffi_new(int_array_t, bucket_sz)
    }
    -- "note_v" is an array of all the nodes used in the LRU queue. Exprpession
    -- node_v[i] evaluates to the element of ID "i".
    self.node_v = self.free_queue

    -- Allocate the array-part of the key_v, val_v, bucket_v.
    local key_v = self.key_v
    local val_v = self.val_v
    local bucket_v = self.bucket_v
    ffi_fill(self.bucket_v, ffi_sizeof(int_t, bucket_sz), 0)

    return setmetatable(self, mt)
end


local function hash_string(self, str)
    local c_str = ffi_cast(c_str_t, str)

    local hv = crc32_ptr(c_str)
    hv = band(hv, self.bucket_sz - 1)
    -- Hint: bucket is 0-based
    return hv
end


-- Search the node associated with the key in the bucket, if found returns
-- the the id of the node, and the id of its previous node in the conflict list.
-- The "bucket_hdr_id" is the ID of the first node in the bucket
local function _find_node_in_bucket(key, key_v, node_v, bucket_hdr_id)
    if bucket_hdr_id ~= 0 then
        local prev = 0
        local cur = bucket_hdr_id

        while cur ~= 0 and key_v[cur] ~= key do
            prev = cur
            cur = node_v[cur].conflict
        end

        if cur ~= 0 then
            return cur, prev
        end
    end
end


-- Return the node corresponding to the key/val.
local function find_key(self, key)
    local key_hash = hash_string(self, key)
    return _find_node_in_bucket(key, self.key_v, self.node_v,
                                self.bucket_v[key_hash])
end


--[[ This function tries to
  1. Remove the given key and the associated value from the key/value store,
  2. Remove the entry associated with the key from the hash-table.

  NOTE: all queues remain intact.

  If there was a node bound to the key/val, return that node; otherwise,
  nil is returned.
]]
local function remove_key(self, key)
    local key_v = self.key_v
    local val_v = self.val_v
    local node_v = self.node_v
    local bucket_v = self.bucket_v

    local key_hash = hash_string(self, key)
    local cur, prev =
        _find_node_in_bucket(key, key_v, node_v, bucket_v[key_hash])

    if cur then
        -- In an attempt to make key and val dead.
        key_v[cur] = nil
        val_v[cur] = nil

        -- Remove the node from the hash table
        local next_node = node_v[cur].conflict
        if prev ~= 0 then
            node_v[prev].conflict = next_node
        else
            bucket_v[key_hash] = next_node
        end
        node_v[cur].conflict = 0

        return cur
    end
end


--[[ Bind the key/val with the given node, and insert the node into the Hashtab.
    NOTE: this function does not touch any queue
]]
local function insert_key(self, key, val, node)
    -- Bind the key/val with the node
    local node_id = node.id
    self.key_v[node_id] = key
    self.val_v[node_id] = val

    -- Insert the node into the hash-table
    local key_hash = hash_string(self, key)
    local bucket_v = self.bucket_v
    node.conflict = bucket_v[key_hash]
    bucket_v[key_hash] = node_id
end


function _M.get(self, key)
    if type(key) ~= "string" then
        key = tostring(key)
    end

    local node_id = find_key(self, key)
    if not node_id then
        return nil
    end

    -- print(key, ": moving node ", tostring(node), " to cache queue head")
    local cache_queue = self.cache_queue
    local node = self.node_v + node_id
    queue_remove(node)
    queue_insert_head(cache_queue, node)

    local expire = node.expire
    if expire >= 0 and expire < ngx_now() then
        -- print("expired: ", node.expire, " > ", ngx_now())
        return nil, self.val_v[node_id]
    end

    return self.val_v[node_id]
end


function _M.delete(self, key)
    if type(key) ~= "string" then
        key = tostring(key)
    end

    local node_id = remove_key(self, key);
    if not node_id then
        return false
    end

    local node = self.node_v + node_id
    queue_remove(node)
    queue_insert_tail(self.free_queue, node)
    return true
end


function _M.set(self, key, value, ttl)
    if type(key) ~= "string" then
        key = tostring(key)
    end

    local node_id = find_key(self, key)
    local node
    if not node_id then
        local free_queue = self.free_queue
        if queue_is_empty(free_queue) then
            -- evict the least recently used key
            -- assert(not queue_is_empty(self.cache_queue))
            node = queue_last(self.cache_queue)
            remove_key(self, self.key_v[node.id])
        else
            -- take a free queue node
            node = queue_head(free_queue)
            -- print(key, ": get a new free node: ", tostring(node))
        end

        -- insert the key
        insert_key(self, key, value, node)
    else
        node = self.node_v + node_id
        self.val_v[node_id] = value
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
