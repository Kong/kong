--- Node-level utilities.
--
-- @module kong.node

local ffi = require "ffi"
local private_node = require "kong.pdk.private.node"
local uuid = require("kong.tools.uuid").uuid
local bytes_to_str = require("kong.tools.string").bytes_to_str


local floor = math.floor
local lower = string.lower
local match = string.match
local gsub = string.gsub
local sort = table.sort
local insert = table.insert
local ngx = ngx
local shared = ngx.shared
local C             = ffi.C
local ffi_new       = ffi.new
local ffi_str       = ffi.string

local NODE_ID_KEY = "kong:node_id"


local node_id
local shms = {}
local n_workers = ngx.worker.count()


ffi.cdef[[
int gethostname(char *name, size_t len);
]]


for shm_name, shm in pairs(shared) do
  insert(shms, {
    zone = shm,
    name = shm_name,
    capacity = shm:capacity(),
  })
end


local function convert_bytes(bytes, unit, scale)
  if not unit or lower(unit) == "b" then
    return floor(bytes)
  end

  return bytes_to_str(bytes, unit, scale)
end


local function sort_pid_asc(a, b)
  return a.pid < b.pid
end


local function new(self)
  local _NODE = {
    hostname = nil,
  }


  ---
  -- Returns the ID used by this node to describe itself.
  --
  -- @function kong.node.get_id
  -- @treturn string The v4 UUID used by this node as its ID.
  -- @usage
  -- local id = kong.node.get_id()
  function _NODE.get_id()
    if node_id then
      return node_id
    end

    local shm = ngx.shared.kong

    local ok, err = shm:safe_add(NODE_ID_KEY, uuid())
    if not ok and err ~= "exists" then
      error("failed to set 'node_id' in shm: " .. err)
    end

    node_id, err = shm:get(NODE_ID_KEY)
    if err then
      error("failed to get 'node_id' in shm: " .. err)
    end

    if not node_id then
      error("no 'node_id' set in shm")
    end

    return node_id
  end


  ---
  -- Returns memory usage statistics about this node.
  --
  -- @function kong.node.get_memory_stats
  -- @tparam[opt] string unit The unit that memory is reported in. Can be
  -- any of `b/B`, `k/K`, `m/M`, or `g/G` for bytes, kibibytes, mebibytes,
  -- or gibibytes, respectively. Defaults to `b` (bytes).
  -- @tparam[opt] number scale The number of digits to the right of the decimal
  -- point. Defaults to 2.
  -- @treturn table A table containing memory usage statistics for this node.
  -- If `unit` is `b/B` (the default), reported values are Lua numbers.
  -- Otherwise, reported values are strings with the unit as a suffix.
  -- @usage
  -- local res = kong.node.get_memory_stats()
  -- -- res will have the following structure:
  -- {
  --   lua_shared_dicts = {
  --     kong = {
  --       allocated_slabs = 12288,
  --       capacity = 24576
  --     },
  --     kong_db_cache = {
  --       allocated_slabs = 12288,
  --       capacity = 12288
  --     }
  --   },
  --   workers_lua_vms = {
  --     {
  --       http_allocated_gc = 1102,
  --       pid = 18004
  --     },
  --     {
  --       http_allocated_gc = 1102,
  --       pid = 18005
  --     }
  --   }
  -- }
  --
  -- local res = kong.node.get_memory_stats("k", 1)
  -- -- res will have the following structure:
  -- {
  --   lua_shared_dicts = {
  --     kong = {
  --       allocated_slabs = "12.0 KiB",
  --       capacity = "24.0 KiB",
  --     },
  --     kong_db_cache = {
  --       allocated_slabs = "12.0 KiB",
  --       capacity = "12.0 KiB",
  --     }
  --   },
  --   workers_lua_vms = {
  --     {
  --       http_allocated_gc = "1.1 KiB",
  --       pid = 18004
  --     },
  --     {
  --       http_allocated_gc = "1.1 KiB",
  --       pid = 18005
  --     }
  --   }
  -- }
  function _NODE.get_memory_stats(unit, scale)
    -- validate arguments

    do
      unit = unit or "b"
      scale = scale or 2

      local pok, perr = pcall(bytes_to_str, 0, unit, scale)
      if not pok then
        error(perr, 2)
      end
    end

    local res = {
      workers_lua_vms = self.table.new(n_workers, 0),
      lua_shared_dicts = self.table.new(0, #shms),
    }

    -- get workers Lua VM allocated memory

    do
      if not shared.kong then
        goto lua_shared_dicts
      end

      local keys, err = shared.kong:get_keys()
      if not keys then
        res.workers_lua_vms.err = "could not get kong shm keys: " .. err
        goto lua_shared_dicts
      end

      if #keys == 1024 then
        -- Preventive warning log for future Kong developers, in case 'kong'
        -- shm becomes mis-used or over-used.
        ngx.log(ngx.WARN, "ngx.shared.kong:get_keys() returned 1024 keys, ",
                          "but it may have more")
      end

      for i = 1, #keys do
        local pid = match(keys[i], "kong:mem:(%d+)")
        if not pid then
          goto continue
        end

        local w = self.table.new(0, 2)
        w.pid = tonumber(pid)

        local count, err = shared.kong:get("kong:mem:" .. pid)
        if err then
          w.err = "could not get worker's HTTP Lua VM memory (pid: " ..
                  pid .. "): " .. err

        elseif type(count) ~= "number" then
          w.err = "could not get worker's HTTP Lua VM memory (pid: " ..
                  pid .. "): reported value is corrupted"

        else
          count = count * 1024 -- reported value is in kb
          w.http_allocated_gc = convert_bytes(count, unit, scale)
        end

        insert(res.workers_lua_vms, w)

        ::continue::
      end

      sort(res.workers_lua_vms, sort_pid_asc)
    end

    -- get lua_shared_dicts allocated slabs
    ::lua_shared_dicts::

    for _, shm in ipairs(shms) do
      local allocated = shm.capacity - shm.zone:free_space()

      res.lua_shared_dicts[shm.name] = {
        capacity = convert_bytes(shm.capacity, unit, scale),
        allocated_slabs = convert_bytes(allocated, unit, scale),
      }
    end

    return res
  end


  ---
  -- Returns the name used by the local machine.
  --
  -- @function kong.node.get_hostname
  -- @treturn string The local machine hostname.
  -- @usage
  -- local hostname = kong.node.get_hostname()
  function _NODE.get_hostname()
    if not _NODE.hostname then
      local SIZE = 253 -- max number of chars for a hostname

      local buf = ffi_new("unsigned char[?]", SIZE)
      local res = C.gethostname(buf, SIZE)

      if res ~= 0 then
        -- Return an empty string "" instead of nil and error message,
        -- because strerror is not thread-safe and the behavior of strerror_r
        -- is inconsistent across different systems.
        return ""
      end

      _NODE.hostname = gsub(ffi_str(buf, SIZE), "%z+$", "")
    end

    return _NODE.hostname
  end


  -- the PDK can be even when there is no configuration (for docs/tests)
  -- so execute below block only when running under correct context
  local prefix = self and self.configuration and self.configuration.prefix
  if prefix  then
    -- precedence order:
    -- 1. user provided node id
    local configuration_node_id = self and self.configuration and self.configuration.node_id
    if configuration_node_id then
      node_id = configuration_node_id
    end
    -- 2. node id (if any) on file-system
    if not node_id then
      if prefix and self.configuration.role == "data_plane" then
        local id, err = private_node.load_node_id(prefix)
        if id then
          node_id = id
          ngx.log(ngx.DEBUG, "restored node_id from the filesystem: ", node_id)
        else
          ngx.log(ngx.WARN, "failed to restore node_id from the filesystem: ",
                  err, ", a new node_id will be generated")
        end
      end
    end
    -- 3. generate a new id
    if not node_id then
      node_id = _NODE.get_id()
    end
    if node_id then
      ngx.log(ngx.INFO, "kong node-id: ", node_id)
    end
  end

  return _NODE
end


return {
  new = new,
}
