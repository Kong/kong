--- Node-level utilities
--
-- @module kong.node

local utils = require "kong.tools.utils"


local floor = math.floor
local lower = string.lower
local match = string.match
local sort = table.sort
local insert = table.insert
local shared = ngx.shared


local NODE_ID_KEY = "kong:node_id"


local node_id
local shms = {}
local n_workers = ngx.worker.count()


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

  return utils.bytes_to_str(bytes, unit, scale)
end


local function sort_pid_asc(a, b)
  return a.pid < b.pid
end


local function new(self)
  local _NODE = {}


  ---
  -- Returns the id used by this node to describe itself.
  --
  -- @function kong.node.get_id
  -- @treturn string The v4 UUID used by this node as its id
  -- @usage
  -- local id = kong.node.get_id()
  function _NODE.get_id()
    if node_id then
      return node_id
    end

    local shm = ngx.shared.kong

    local ok, err = shm:safe_add(NODE_ID_KEY, utils.uuid())
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
  -- @tparam[opt] string unit The unit memory should be reported in. Can be
  -- either of `b/B`, `k/K`, `m/M`, or `g/G` for bytes, kibibytes, mebibytes,
  -- or gibibytes, respectively. Defaults to `b` (bytes).
  -- @tparam[opt] number scale The number of digits to the right of the decimal
  -- point. Defaults to 2.
  -- @treturn table A table containing memory usage statistics for this node.
  -- If `unit` is `b/B` (the default) reported values will be Lua numbers.
  -- Otherwise, reported values will be a string with the unit as a suffix.
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

      local pok, perr = pcall(utils.bytes_to_str, 0, unit, scale)
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


  return _NODE
end


return {
  new = new,
}
