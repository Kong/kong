local cjson = require("cjson.safe")
local ngx_ssl = require("ngx.ssl")
local basic_serializer = require "kong.plugins.log-serializers.basic"
local msgpack = require "MessagePack"
local reports = require "kong.reports"


local kong = kong
local ngx = ngx
local ngx_timer_at = ngx.timer.at
local cjson_encode = cjson.encode
local mp_pack = msgpack.pack
local mp_unpacker = msgpack.unpacker


local go = {}


local reset_instances   -- forward declaration
local preloaded_stuff = {}


-- add MessagePack empty array/map

msgpack.packers['function'] = function (buffer, f)
  f(buffer)
end

local function mp_empty_array(buffer)
  msgpack.packers['array'](buffer, {}, 0)
end

local function mp_empty_map(buffer)
  msgpack.packers['map'](buffer, {}, 0)
end


--- is_on(): returns true if Go plugins is enabled
function go.is_on()
  return kong.configuration.go_plugins_dir ~= "off"
end


do
  local __socket_path
  --- socket_path(): returns the (hardcoded) socket pathname
  function go.socket_path()
    __socket_path = __socket_path or kong.configuration.prefix .. "/go_pluginserver.sock"
    return __socket_path
  end
end

do
  local function get_pluginserver_go_version()
    local cmd = string.format("%s -version", kong.configuration.go_pluginserver_exe)
    local fd = assert(io.popen(cmd))
    local out = fd:read("*a")
    fd:close()

    return out:match("Runtime Version: go(.+)\n$")
  end

  local pluginserver_proc

  function go.manage_pluginserver()
    assert(not pluginserver_proc, "Don't call go.manage_pluginserver() more than once.")

    reports.add_immutable_value("go_version", get_pluginserver_go_version())

    if ngx.worker.id() ~= 0 then
      -- only one manager
      pluginserver_proc = true
      return
    end

    ngx_timer_at(0, function(premature)
      if premature then
        return
      end

      local ngx_pipe = require "ngx.pipe"

      while not ngx.worker.exiting() do
        kong.log.notice("Starting go-pluginserver")
        pluginserver_proc = assert(ngx_pipe.spawn({
          kong.configuration.go_pluginserver_exe,
          "-kong-prefix", kong.configuration.prefix,
          "-plugins-directory", kong.configuration.go_plugins_dir,
        }))
        pluginserver_proc:set_timeouts(nil, nil, nil, 0)     -- block until something actually happens

        while true do
          local ok, reason, status = pluginserver_proc:wait()
          if ok ~= nil or reason == "exited" then
            kong.log.notice("go-pluginserver terminated: ", tostring(reason), " ", tostring(status))
            break
          end
        end
      end
      kong.log.notice("Exiting: go-pluginserver not respawned.")
    end)

  end
end


-- This is the MessagePack-RPC implementation
local rpc_call
do
  local msg_id = 0

  local notifications = {}

  do
    local pluginserver_pid
    function notifications.serverPid(n)
      n = tonumber(n)
      if pluginserver_pid and n ~= pluginserver_pid then
        reset_instances()
      end

      pluginserver_pid = n
    end
  end

  -- This function makes a RPC call to the Go plugin server. The Go plugin
  -- server communication is request driven from the Kong side. Kong first
  -- sends the RPC request, then it executes any PDK calls from Go code
  -- in the while loop below. The boundary of a RPC call is reached once
  -- the RPC response (type 1) message is seen. After that the connection
  -- is kept alive waiting for the next RPC call to be initiated by Kong.
  function rpc_call(method, ...)
    msg_id = msg_id + 1
    local my_msg_id = msg_id

    local c, err = ngx.socket.connect("unix:" .. go.socket_path())
    if not c then
      kong.log.err("trying to connect: ", err)
      return nil, err
    end

    local bytes, err = c:send(mp_pack({0, my_msg_id, method, {...}}))
    if not bytes then
      c:setkeepalive()
      return nil, err
    end

    local reader = mp_unpacker(function()
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

      else
        assert(data[1] == 1, "RPC response expected from Go plugin server")
        assert(data[2] == my_msg_id,
               "unexpected RPC response ID from Go plugin server")

        -- it's our answer
        c:setkeepalive()

        if data[3] ~= nil then
          return nil, data[3]
        end

        return data[4]
      end
    end
  end
end


local function fix_mmap(t)
  local o, empty = {}, true

  for k, v in pairs(t) do
    empty = false
    if v == true then
      o[k] = mp_empty_array

    elseif type(v) == "string" then
      o[k] = { v }

    else
      o[k] = v
    end
  end

  if empty then
    return mp_empty_map
  end

  return o
end


-- global method search and cache
local function index_table(table, field)
  if table[field] then
    return table[field]
  end

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
    ["kong.log.serialize"] = function()
      return cjson_encode(preloaded_stuff.basic_serializer or basic_serializer.serialize(ngx))
    end,

    ["kong.nginx.get_var"] = function(v)
      return ngx.var[v]
    end,

    ["kong.nginx.get_tls1_version_str"] = ngx_ssl.get_tls1_version_str,

    ["kong.nginx.get_ctx"] = function(v)
      return ngx.ctx[v]
    end,

    ["kong.nginx.req_start_time"] = ngx.req.start_time,

    ["kong.request.get_query"] = function(max)
      return fix_mmap(kong.request.get_query(max))
    end,

    ["kong.request.get_headers"] = function(max)
      return fix_mmap(kong.request.get_headers(max))
    end,

    ["kong.response.get_headers"] = function(max)
      return fix_mmap(kong.response.get_headers(max))
    end,

    ["kong.service.response.get_headers"] = function(max)
      return fix_mmap(kong.service.response.get_headers(max))
    end,
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
  local method = get_field(cmd)
  if not method then
    kong.log.err("could not find pdk method: ", cmd)
    return
  end

  if type(args) == "table" then
    return method(unpack(args))
  end

  return method(args)
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
    ["kong.request.get_query"] = "plugin.StepMultiMap",
    ["kong.request.get_headers"] = "plugin.StepMultiMap",
    ["kong.response.get_headers"] = "plugin.StepMultiMap",
    ["kong.service.response.get_headers"] = "plugin.StepMultiMap",
  }

  function get_step_method(step_in, pdk_res, pdk_err)
    if not pdk_res and pdk_err then
      return "plugin.StepError", pdk_err
    end

    return ((type(pdk_res) == "table" and pdk_res._method)
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

  local function get_plugin_info(name)
    local cmd = string.format(
        "%s -plugins-directory %q -dump-plugin-info %q",
        kong.configuration.go_pluginserver_exe, kong.configuration.go_plugins_dir, name)

    local fd = assert(io.popen(cmd))
    local d = fd:read("*a")
    fd:close()

    return assert(msgpack.unpack(d))
  end

  function get_plugin(plugin_name)
    local plugin = loaded_plugins[plugin_name]
    if plugin and plugin.PRIORITY then
      return plugin
    end

    local plugin_info = get_plugin_info(plugin_name)

    plugin = {
      PRIORITY = plugin_info.Priority,
      VERSION = plugin_info.Version,
      schema = plugin_info.Schema,
    }

    for _, phase in ipairs(plugin_info.Phases) do
      if phase == "log" then
        plugin[phase] = function(self, conf)
          preloaded_stuff.basic_serializer = basic_serializer.serialize(ngx)
          ngx_timer_at(0, function()
            local instance_id = get_instance(plugin_name, conf)
            bridge_loop(instance_id, phase)
            preloaded_stuff.basic_serializer = nil
          end)
        end

      else
        plugin[phase] = function(self, conf)
          local instance_id = get_instance(plugin_name, conf)
          bridge_loop(instance_id, phase)
        end
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
