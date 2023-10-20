--- Node-level utilities.
--
-- @module kong.node

local utils = require "kong.tools.utils"
local ffi = require "ffi"
local private_node = require "kong.pdk.private.node"


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
    local SIZE = 253 -- max number of chars for a hostname

    local buf = ffi_new("unsigned char[?]", SIZE)
    local res = C.gethostname(buf, SIZE)

    if res == 0 then
      local hostname = ffi_str(buf, SIZE)
      return gsub(hostname, "%z+$", "")
    end

    local f = io.popen("/bin/hostname")
    local hostname = f:read("*a") or ""
    f:close()
    return gsub(hostname, "\n$", "")
  end

  ---
  -- Returns `true` if a node is a data plane node.
  --
  -- @function kong.node.is_data_plane
  -- @treturn boolean `true` if a node is a data plane node, otherwise `false`.
  -- @usage
  -- if kong.node.is_data_plane() then
  --   ...
  -- end
  local function is_data_plane()
    return self.configuration.role == "data_plane"
  end
  _NODE.is_data_plane = is_data_plane


  ---
  -- Returns `true` if a node is not a data plane node.
  --
  -- @function kong.node.is_not_data_plane
  -- @treturn boolean `true` if a node is not a data plane node, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_data_plane() then
  --   ...
  -- end
  local function is_not_data_plane()
    return not is_data_plane()
  end
  _NODE.is_not_data_plane = is_not_data_plane


  ---
  -- Returns `true` if a node is a control plane node.
  --
  -- @function kong.node.is_control_plane
  -- @treturn boolean `true` if a node is a control plane node, otherwise `false`.
  -- @usage
  -- if kong.node.is_control_plane() then
  --   ...
  -- end
  local function is_control_plane()
    return self.configuration.role == "control_plane"
  end
  _NODE.is_control_plane = is_control_plane


  ---
  -- Returns `true` if a node is not a control plane node.
  --
  -- @function kong.node.is_not_control_plane
  -- @treturn boolean `true` if a node is not a control plane node, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_control_plane() then
  --   ...
  -- end
  local function is_not_control_plane()
    return not is_control_plane()
  end
  _NODE.is_not_control_plane = is_not_control_plane


  ---
  -- Returns `true` if a node is a traditional node.
  --
  -- @function kong.node.is_traditional
  -- @treturn boolean `true` if a node is a traditional node, otherwise `false`.
  -- @usage
  -- if kong.node.is_traditional() then
  --   ...
  -- end
  local function is_traditional()
    return self.configuration.role == "traditional"
  end
  _NODE.is_traditional = is_traditional


  -- Returns `true` if a node is not a traditional node.
  --
  -- @function kong.node.is_not_traditional
  -- @treturn boolean `true` if a node is not a traditional node, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_traditional() then
  --   ...
  -- end
  local function is_not_traditional()
    return not is_traditional()
  end
  _NODE.is_not_traditional = is_not_traditional


  ---
  -- Returns `true` if a node is a dbless node.
  --
  -- *Note:* both data plane and non-hybrid dbless nodes are considered as dbless.
  --
  -- @function kong.node.is_dbless
  -- @treturn boolean `true` if a node is a dbless node, otherwise `false`.
  -- @usage
  -- if kong.node.is_dbless() then
  --   ...
  -- end
  local function is_dbless()
    return self.configuration.database == "off"
  end
  _NODE.is_dbless = is_dbless


  ---
  -- Returns `true` if a node is not a dbless node.
  --
  -- *Note:* both data plane and non-hybrid dbless nodes are considered as dbless.
  --
  -- @function kong.node.is_not_dbless
  -- @treturn boolean `true` if a node is not a dbless node, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_dbless() then
  --   ...
  -- end
  local function is_not_dbless()
    return not is_dbless()
  end
  _NODE.is_not_dbless = is_not_dbless


  ---
  -- Returns `true` if a node is either a control plane node or a data plane node.
  --
  -- @function kong.node.is_hybrid
  -- @treturn boolean `true` if a node is a hybrid node, otherwise `false`.
  -- @usage
  -- if kong.node.is_hybrid() then
  --   ...
  -- end
  local function is_hybrid()
    return is_data_plane() or is_control_plane()
  end
  _NODE.is_hybrid = is_hybrid


  ---
  -- Returns `true` if a node is neither a control plane node or a data plane node.
  --
  -- @function kong.node.is_not_hybrid
  -- @treturn boolean `true` if a node is not a hybrid node, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_hybrid() then
  --   ...
  -- end
  local function is_not_hybrid()
    return not is_hybrid()
  end
  _NODE.is_not_hybrid = is_not_hybrid


  ---
  -- Returns `true` if a node is serving (or proxying) http traffic.
  --
  -- @function kong.node.is_serving_http_traffic
  -- @treturn boolean `true` if a node is serving http traffic, otherwise `false`.
  -- @usage
  -- if kong.node.is_serving_http_traffic() then
  --   ...
  -- end
  local function is_serving_http_traffic()
    return (is_data_plane() or is_traditional()) and #self.configuration.proxy_listeners > 0
  end
  _NODE.is_serving_http_traffic = is_serving_http_traffic


  ---
  -- Returns `true` if a node is not serving (or proxying) http traffic.
  --
  -- @function kong.node.is_not_serving_http_traffic
  -- @treturn boolean `true` if a node is not serving http traffic, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_serving_http_traffic() then
  --   ...
  -- end
  local function is_not_serving_http_traffic()
    return not is_serving_http_traffic()
  end
  _NODE.is_not_serving_http_traffic = is_not_serving_http_traffic


  ---
  -- Returns `true` if a node is serving (or proxying) stream (tcp/udp) traffic.
  --
  -- @function kong.node.is_serving_stream_traffic
  -- @treturn boolean `true` if a node is serving stream (tcp/udp) traffic, otherwise `false`.
  -- @usage
  -- if kong.node.is_serving_stream_traffic() then
  --   ...
  -- end
  local function is_serving_stream_traffic()
    return (is_data_plane() or is_traditional()) and #self.configuration.stream_listeners > 0
  end
  _NODE.is_serving_stream_traffic = is_serving_stream_traffic


  ---
  -- Returns `true` if a node is not serving (or proxying) stream (tcp/udp) traffic.
  --
  -- @function kong.node.is_not_serving_stream_traffic
  -- @treturn boolean `true` if a node is not able to proxy stream (tcp/udp) traffic, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_serving_stream_traffic() then
  --   ...
  -- end
  local function is_not_serving_stream_traffic()
    return not is_serving_stream_traffic()
  end
  _NODE.is_not_serving_stream_traffic = is_not_serving_stream_traffic


  ---
  -- Returns `true` if a node is serving (or proxying) http and/or stream (tcp/udp) traffic.
  --
  -- @function kong.node.is_serving_proxy_traffic
  -- @treturn boolean `true` if a node is serving (or proxying) http and/or stream (tcp/udp) traffic, otherwise `false`.
  -- @usage
  -- if kong.node.is_serving_proxy_traffic() then
  --   ...
  -- end
  local function is_serving_proxy_traffic()
    return is_serving_http_traffic() or is_serving_stream_traffic()
  end
  _NODE.is_serving_proxy_traffic = is_serving_proxy_traffic


  ---
  -- Returns `true` if a node is not serving (or proxying) http or stream (tcp/udp) traffic.
  --
  -- @function kong.node.is_not_serving_proxy_traffic
  -- @treturn boolean `true` if a node is not serving (or proxying) http or stream (tcp/udp) traffic, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_serving_proxy_traffic() then
  --   ...
  -- end
  local function is_not_serving_proxy_traffic()
    return not is_serving_proxy_traffic()
  end
  _NODE.is_not_serving_proxy_traffic = is_not_serving_proxy_traffic


  ---
  -- Returns `true` if a node is serving admin APIs.
  --
  -- *Note:* Non-hybrid dbless nodes can also serve (mostly read-only) admin APIs
  -- in addition to control plane and traditional admin nodes.
  --
  -- @function kong.node.is_serving_admin_apis
  -- @treturn boolean `true` if a node is serving admin APIs, otherwise `false`.
  -- @usage
  -- if kong.node.is_serving_admin_apis() then
  --   ...
  -- end
  local function is_serving_admin_apis()
    return (is_control_plane() or is_traditional()) and #self.configuration.admin_listeners > 0
  end
  _NODE.is_serving_admin_apis = is_serving_admin_apis


  ---
  -- Returns `true` if a node is not serving admin APIs.
  --
  -- *Note:* Non-hybrid dbless nodes can also serve (mostly read-only) admin APIs
  -- in addition to control plane and traditional admin nodes.
  --
  -- @function kong.node.is_not_serving_admin_apis
  -- @treturn boolean `true` if a node is not serving admin APIs, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_serving_admin_apis() then
  --   ...
  -- end
  local function is_not_serving_admin_apis()
    return not is_serving_admin_apis()
  end
  _NODE.is_not_serving_admin_apis = is_not_serving_admin_apis


  ---
  -- Returns `true` if a node is serving admin GUI.
  --
  -- @function kong.node.is_serving_admin_gui
  -- @treturn boolean `true` if a node is serving admin GUI, otherwise `false`.
  -- @usage
  -- if kong.node.is_serving_admin_gui() then
  --   ...
  -- end
  local function is_serving_admin_gui()
    return is_serving_admin_apis() and #self.configuration.admin_gui_listeners > 0
  end
  _NODE.is_serving_admin_gui = is_serving_admin_gui


  ---
  -- Returns `true` if a node is not serving admin GUI.
  --
  -- @function kong.node.is_not_serving_admin_gui
  -- @treturn boolean `true` if a node is not serving admin GUI, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_serving_admin_gui() then
  --   ...
  -- end
  local function is_not_serving_admin_gui()
    return not is_serving_admin_gui()
  end
  _NODE.is_not_serving_admin_gui = is_not_serving_admin_gui


  ---
  -- Returns `true` if a node is serving status APIs.
  --
  -- @function kong.node.is_serving_status_apis
  -- @treturn boolean `true` if a node is serving admin APIs, otherwise `false`.
  -- @usage
  -- if kong.node.is_serving_status_apis() then
  --   ...
  -- end
  local function is_serving_status_apis()
    return #self.configuration.status_listeners > 0
  end
  _NODE.is_serving_status_apis = is_serving_status_apis


  ---
  -- Returns `true` if a node is not serving status APIs.
  --
  -- @function kong.node.is_not_serving_status_apis
  -- @treturn boolean `true` if a node is not serving admin APIs, otherwise `false`.
  -- @usage
  -- if kong.node.is_not_serving_status_apis() then
  --   ...
  -- end
  local function is_not_serving_status_apis()
    return not is_serving_status_apis()
  end
  _NODE.is_not_serving_status_apis = is_not_serving_status_apis


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
      ngx.log(ngx.INFO, "kong node-id: " .. node_id)
    end
  end

  return _NODE
end


return {
  new = new,
}
