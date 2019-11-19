local ffi = require("ffi")
local cjson = require("cjson.safe")
local ngx_ssl = require("ngx.ssl")
local basic_serializer = require "kong.plugins.log-serializers.basic"
local msgpack = require "MessagePack"


local go = {}


local C = ffi.C
local kong = kong
local ngx = ngx
local cjson_encode = cjson.encode
local mp_pack = msgpack.pack
local mp_unpacker = msgpack.unpacker

local reset_instances   -- forward declaration


-- Workaround: if cosockets aren't available, use raw glibc calls
local get_connection
do
  pcall(ffi.cdef, [[
    static int const AF_UNIX = 1;
    static int const SOCK_STREAM = 1;

    struct sockaddr_un {
      uint16_t  sun_family;               /* AF_UNIX */
      char      sun_path[108];            /* pathname */
    };

    typedef struct ffi_sock {
      int fd;
    } ffi_sock;

    int socket(int domain, int type, int protocol);
    int connect(int sockfd, const void *addr, uint32_t addrlen);
    ssize_t write(int fd, const void *buf, size_t count);
    ssize_t read(int fd, void *buf, size_t count);
    int close(int fd);
  ]])

  local ffi_sock = ffi.typeof("ffi_sock")

  local function un_addr(path)
    local conaddr = ffi.new('struct sockaddr_un')
    if conaddr == nil then
      return nil, "can't allocate sockaddr_un"
    end

    conaddr.sun_family = C.AF_UNIX

    local len = #path + 1
    if len > 107 then
      len = 107
    end
    ffi.copy(conaddr.sun_path, path, len)
    return conaddr
  end

  pcall(ffi.metatype, ffi_sock, {
    __new = function (ct, path)
      local fd = C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
      if fd < 0 then
        return nil, "can't create socket"
      end

      local conaddr = un_addr(path)
      local res = C.connect(fd, conaddr, ffi.sizeof(conaddr))
      if res < 0 then
        C.close(fd)
        local errno = ffi.errno()
        return nil, "connect failure: " .. ffi.string(C.strerror(errno))
      end

      return ffi.new(ct, fd)
    end,

    __index = {
      send = function (self, s)
        local p = ffi.cast('const uint8_t *', s)
        local sent_bytes = 0
        while sent_bytes < #s do
          local rc = C.write(self.fd, p+sent_bytes, #s-sent_bytes)
          if rc < 0 then
            local errno = ffi.errno()
            return nil, "error writing to socket: " .. ffi.string(C.strerror(errno))
          end
          sent_bytes = sent_bytes + rc
        end
        return sent_bytes
      end,

      receiveany = function (self, n)
        local buf = ffi.new('uint8_t[?]', n)
        if buf == nil then
          return nil, "can't allocate buffer."
        end

        local rc = C.read(self.fd, buf, n)
        if rc < 0 then
          return nil, "error reading"
        end
        return ffi.string(buf, rc)
      end,

      setkeepalive = function (self)
        if self.fd ~= -1 then
          C.close(self.fd)
          self.fd = -1
        end
      end,
    },

    __gc = function (self)
      self:setkeepalive()
    end,
  })

  local too_early = {
    init = true,
    init_worker = true,
    set = true,
    header_filter = true,
    body_filter = true,
    log = true,
  }

  function get_connection(socket_path)
    if too_early[ngx.get_phase()] then
      return ffi_sock(socket_path)
    end

    return ngx.socket.connect("unix:" .. socket_path)
  end
end
go.get_connection = get_connection


-- This is the MessagePack-RPC implementation
local rpc_call
local set_plugin_dir
do
  local msg_id = 0

  local notifications = {}

  local current_plugin_dir

  do
    local pluginserver_pid
    function notifications.serverPid(n)
      n = tonumber(n)
      if pluginserver_pid and n ~= pluginserver_pid then
        reset_instances()
        current_plugin_dir = nil
      end

      pluginserver_pid = n
    end
  end

  function rpc_call(method, ...)
    msg_id = msg_id + 1
    local my_msg_id = msg_id

    local c = assert(get_connection(kong.configuration.pluginserver_socket))
    local bytes, err = c:send(mp_pack({0, my_msg_id, method, {...}}))
    if not bytes then
      c:setkeepalive()
      return nil, err
    end

    local reader = mp_unpacker(function ()
      return c:receiveany(4096)
    end)

    while true do
      local ok, data = reader()
      if not ok then
        c:setkeepalive()
        return nil, data
      end

      if data[1] == 2 then
        -- it's a notification message, act on it
        local f = notifications[data[2]]
        if f then
          f(data[3])
        end
      end

      if data[1] == 1 and data[2] == my_msg_id then
        -- it's our answer
        if data[3] ~= nil then
          c:setkeepalive()
          return nil, data[3]
        end

        c:setkeepalive()
        return data[4]
      end
    end
  end

  function set_plugin_dir(dir)
    if dir == current_plugin_dir then
      return
    end

    local res, err = rpc_call("plugin.SetPluginDir", dir)
    if not res then
      kong.log.err("Setting Go plugin dir: ", err)
      error(err)
    end

    current_plugin_dir = dir
  end
end

-- global method search and cache
local function index_table(table, field)
  local res = table
  for segment, e in ngx.re.gmatch(field, "\\w+", "o") do
    if res[segment[0]] then
      res = res[segment[0]]
    else
      return nil
    end
  end
  return res
end


local get_field
do
  local exposed_api = {
    kong = kong,
  }

  local method_cache = {}

  function get_field(method)
    if method_cache[method] then
      return method_cache[method]

    else
      method_cache[method] = index_table(exposed_api, method)
      return method_cache[method]
    end
  end
end


local function call_pdk_method(cmd, args)
  local res, err

  if cmd == "kong.log.serialize" then
    res = cjson_encode(basic_serializer.serialize(ngx))

  -- ngx API
  elseif cmd == "kong.nginx.get_var" then
    res = ngx.var[args[1]]

  elseif cmd == "kong.nginx.get_tls1_version_str" then
    res = ngx_ssl.get_tls1_version_str()

  elseif cmd == "kong.nginx.get_ctx" then
    res = ngx.ctx[args[1]]

  elseif cmd == "kong.nginx.req_start_time" then
    res = ngx.req.start_time()

  -- PDK
  else
    local method = get_field(cmd)
    if not method then
      kong.log.err("could not find pdk method: ", cmd)
      return
    end

    if type(args) == "table" then
      res, err = method(unpack(args))
    else
      res, err = method(args)
    end
  end

  return res, err
end


-- return objects via the appropriately typed StepXXX method
local get_step_method
do
  local by_pdk_method = {
    ["kong.client.get_credential"] = "plugin.StepCredential",
    ["kong.client.load_consumer"] = "plugin.StepConsumer",
    ["kong.client.get_consumer"] = "plugin.StepConsumer",
    ["kong.client.authenticate"] = "plugin.StepCredential",
    ["kong.node.get_memory_stats"] = "plugin.StepMemoryStats",
    ["kong.router.get_route"] = "plugin.StepRoute",
    ["kong.router.get_service"] = "plugin.StepService",
  }

  function get_step_method(step_in, pdk_res, pdk_err)
    if not pdk_res and pdk_err then
      return "plugin.StepError", pdk_err
    end

    return ((pdk_res and pdk_res._method)
        or by_pdk_method[step_in.Data.Method]
        or "plugin.Step"), pdk_res
  end
end


local function bridge_loop(instance_id, phase)
  local step_in, err = rpc_call("plugin.HandleEvent", {
    InstanceId = instance_id,
    EventName = phase,
  })
  if not step_in then
    return step_in, err
  end

  local event_id = step_in.EventId

  while true do
    if step_in.Data == "ret" then
      break
    end

    local pdk_res, pdk_err = call_pdk_method(
      step_in.Data.Method,
      step_in.Data.Args)

    local step_method, step_res = get_step_method(step_in, pdk_res, pdk_err)

    step_in, err = rpc_call(step_method, {
      EventId = event_id,
      Data = step_res,
    })
    if not step_in then
      return step_in, err
    end
  end
end

-- find a plugin instance for this specific configuration
-- if it's a new config, start a new instance
-- returns: the instance ID
local get_instance
do
  local instances = {}

  function reset_instances()
    instances = {}
  end

  function get_instance(plugin_name, conf)
    local key = type(conf) == "table" and conf.__key__ or plugin_name
    local instance_info = instances[key]

    while instance_info and not instance_info.id do
      -- some other thread is already starting an instance
      ngx.sleep(0)
      if not instances[key] then
        break
      end
    end

    if instance_info
      and instance_info.id
      and instance_info.seq == instance_info.conf.__seq__
    then
      -- exact match, return it
      return instance_info.id
    end

    local old_instance_id = instance_info and instance_info.id
    if not instance_info then
      -- we're the first, put something to claim
      instance_info = {
        conf = conf,
        seq = conf.__seq__,
      }
      instances[key] = instance_info
    else

      -- there already was something, make it evident that we're changing it
      instance_info.id = nil
    end

    set_plugin_dir(kong.configuration.go_plugins_dir)
    local status, err = rpc_call("plugin.StartInstance", {
      Name = plugin_name,
      Config = cjson_encode(conf)
    })
    if status == nil then
      kong.log.err("starting instance: ", err)
      -- remove claim, some other thread might succeed
      instances[key] = nil
      error(err)
    end

    instance_info.id = status.Id
    instance_info.Config = status.Config

    if old_instance_id then
      -- there was a previous instance with same key, close it
      rpc_call("plugin.CloseInstance", old_instance_id)
      -- don't care if there's an error, maybe other thread closed it first.
    end

    return status.Id
  end
end


-- get plugin info (handlers, schema, etc)
local get_plugin do
  local loaded_plugins = {}

  function get_plugin(plugin_name)
    local plugin = loaded_plugins[plugin_name]
    if plugin and plugin.PRIORITY then
      return plugin
    end

    set_plugin_dir(kong.configuration.go_plugins_dir)
    local plugin_info, err = rpc_call("plugin.GetPluginInfo", plugin_name)
    if not plugin_info then
      kong.log.err("calling GetPluginInfo: ", err)
      return nil, err
    end

    plugin = {
      PRIORITY = plugin_info.Priority,
      VERSION = plugin_info.Version,
      schema = plugin_info.Schema,
    }

    for _, phase in ipairs(plugin_info.Phases) do
      plugin[phase] = function (self, conf)
        local instance_id = get_instance(plugin_name, conf)
        bridge_loop(instance_id, phase)
      end
    end

    loaded_plugins[plugin_name] = plugin
    return plugin
  end
end


function go.load_plugin(plugin_name)
  local plugin = get_plugin(plugin_name)
  if plugin and plugin.PRIORITY then
    return true, plugin
  end

  return nil, "not yet"
end

function go.load_schema(plugin_name)
  local plugin = get_plugin(plugin_name)
  if plugin and plugin.PRIORITY then
    return true, plugin.schema
  end

  return nil, "not yet"
end

return go
