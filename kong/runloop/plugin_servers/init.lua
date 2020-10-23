local cjson = require "cjson.safe"
local ngx_ssl = require "ngx.ssl"

local proc_mgmt = require "kong.runloop.plugin_servers.process"
local rpc = require "kong.runloop.plugin_servers.mp_rpc"

local ngx = ngx
local kong = kong
local unpack = unpack
local get_plugin_info = proc_mgmt.get_plugin_info
local ngx_timer_at = ngx.timer.at
local cjson_encode = cjson.encode

--- keep request data a bit longer, into the log timer
local save_for_later = {}

--- handle notifications from pluginservers
local rpc_notifications = {}

--- currently running plugin instances
local running_instances = {}



--[[

RPC

Each plugin server specifies a socket path to communicate.  Protocol is the same
as Go plugins.

CONSIDER:

- when a plugin server notifies a new PID, Kong should request all plugins info again.
  Should it use RPC at this time, instead of commandline?

- Should we add a new notification to ask kong to request plugin info again?

--]]


local function get_server_rpc(server_def)
  if not server_def.rpc then
    server_def.rpc = rpc.new(server_def.socket, rpc_notifications)
    --kong.log.debug("server_def: ", server_def, "   .rpc: ", server_def.rpc)
  end

  return server_def.rpc
end



--- get_instance_id: gets an ID to reference a plugin instance running in a
--- pluginserver each configuration in the database is handled by a different
--- instance.  Biggest complexity here is due to the remote (and thus non-atomic
--- and fallible) operation of starting the instance at the server.
local function get_instance_id(plugin_name, conf)
  local key = type(conf) == "table" and conf.__key__ or plugin_name
  local instance_info = running_instances[key]

  while instance_info and not instance_info.id do
    -- some other thread is already starting an instance
    ngx.sleep(0)
    instance_info = running_instances[key]
  end

  if instance_info
    and instance_info.id
    and instance_info.seq == conf.__seq__
  then
    -- exact match, return it
    return instance_info.id
  end

  local old_instance_id = instance_info and instance_info.id
  if not instance_info then
    -- we're the first, put something to claim
    instance_info          = {
      conf = conf,
      seq = conf.__seq__,
    }
    running_instances[key] = instance_info
  else

    -- there already was something, make it evident that we're changing it
    instance_info.id = nil
  end

  local plugin_info = get_plugin_info(plugin_name)
  local server_rpc  = get_server_rpc(plugin_info.server_def)

  local status, err = server_rpc:call("plugin.StartInstance", {
    Name = plugin_name,
    Config = cjson_encode(conf)
  })
  if status == nil then
    kong.log.err("starting instance: ", err)
    -- remove claim, some other thread might succeed
    running_instances[key] = nil
    error(err)
  end

  instance_info.id = status.Id
  instance_info.conf = conf
  instance_info.seq = conf.__seq__
  instance_info.Config = status.Config
  instance_info.rpc = server_rpc

  if old_instance_id then
    -- there was a previous instance with same key, close it
    server_rpc:call("plugin.CloseInstance", old_instance_id)
    -- don't care if there's an error, maybe other thread closed it first.
  end

  return status.Id
end

--- reset_instance: removes an instance from the table.
local function reset_instance(plugin_name, conf)
  local key = type(conf) == "table" and conf.__key__ or plugin_name
  running_instances[key] = nil
end


--- serverPid notification sent by the pluginserver.  if it changes,
--- all instances tied to this RPC socket should be restarted.
function rpc_notifications:serverPid(n)
  n = tonumber(n)
  if self.pluginserver_pid and n ~= self.pluginserver_pid then
    for key, instance in pairs(running_instances) do
      if instance.rpc == self then
        running_instances[key] = nil
      end
    end
  end

  self.pluginserver_pid = n
end



--[[

Kong API exposed to external plugins

--]]


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
      local saved = save_for_later[coroutine.running()]
      return cjson_encode(saved and saved.serialize_data or kong.log.serialize())
    end,

    ["kong.nginx.get_var"] = function(v)
      return ngx.var[v]
    end,

    ["kong.nginx.get_tls1_version_str"] = ngx_ssl.get_tls1_version_str,

    ["kong.nginx.get_ctx"] = function(k)
      local saved = save_for_later[coroutine.running()]
      local ngx_ctx = saved and saved.ngx_ctx or ngx.ctx
      return ngx_ctx[k]
    end,

    ["kong.nginx.set_ctx"] = function(k, v)
      local saved = save_for_later[coroutine.running()]
      local ngx_ctx = saved and saved.ngx_ctx or ngx.ctx
      ngx_ctx[k] = v
    end,

    ["kong.ctx.shared.get"] = function(k)
      local saved = save_for_later[coroutine.running()]
      local ctx_shared = saved and saved.ctx_shared or kong.ctx.shared
      return ctx_shared[k]
    end,

    ["kong.ctx.shared.set"] = function(k, v)
      local saved = save_for_later[coroutine.running()]
      local ctx_shared = saved and saved.ctx_shared or kong.ctx.shared
      ctx_shared[k] = v
    end,

    ["kong.nginx.req_start_time"] = ngx.req.start_time,

    ["kong.request.get_query"] = function(max)
      return rpc.fix_mmap(kong.request.get_query(max))
    end,

    ["kong.request.get_headers"] = function(max)
      return rpc.fix_mmap(kong.request.get_headers(max))
    end,

    ["kong.response.get_headers"] = function(max)
      return rpc.fix_mmap(kong.response.get_headers(max))
    end,

    ["kong.service.response.get_headers"] = function(max)
      return rpc.fix_mmap(kong.service.response.get_headers(max))
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



--[[

--- Event loop -- instance reconnection

--]]

local function bridge_loop(instance_rpc, instance_id, phase)
  if not instance_rpc then
    kong.log.err("no instance_rpc: ", debug.traceback())
  end
  local step_in, err = instance_rpc:call("plugin.HandleEvent", {
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

    step_in, err = instance_rpc:call(step_method, {
      EventId = event_id,
      Data = step_res,
    })
    if not step_in then
      return step_in, err
    end
  end
end


local function handle_event(instance_rpc, plugin_name, conf, phase)
  local instance_id = get_instance_id(plugin_name, conf)
  local _, err = bridge_loop(instance_rpc, instance_id, phase)

  if err then
    kong.log.err(err)

    if string.match(err, "No plugin instance") then
      reset_instance(plugin_name, conf)
      return handle_event(instance_rpc, plugin_name, conf, phase)
    end
  end
end


--- Phase closures
local function build_phases(plugin)
  if not plugin then
    return
  end

  local server_rpc = get_server_rpc(plugin.server_def)

  for _, phase in ipairs(plugin.phases) do
    if phase == "log" then
      plugin[phase] = function(self, conf)
        local saved = {
          serialize_data = kong.log.serialize(),
          ngx_ctx = ngx.ctx,
          ctx_shared = kong.ctx.shared,
        }

        ngx_timer_at(0, function()
          local co = coroutine.running()
          save_for_later[co] = saved

          handle_event(server_rpc, self.name, conf, phase)

          save_for_later[co] = nil
        end)
      end

    else
      plugin[phase] = function(self, conf)
        handle_event(server_rpc, self.name, conf, phase)
      end
    end
  end

  return plugin
end



--- module table
local plugin_servers = {}


local loaded_plugins = {}

local function get_plugin(plugin_name)
  if not loaded_plugins[plugin_name] then
    local plugin = get_plugin_info(plugin_name)
    loaded_plugins[plugin_name] = build_phases(plugin)
  end

  return loaded_plugins[plugin_name]
end

function plugin_servers.load_plugin(plugin_name)
  local plugin = get_plugin(plugin_name)
  if plugin and plugin.PRIORITY then
    return true, plugin
  end

  return false, "no plugin found"
end

function plugin_servers.load_schema(plugin_name)
  local plugin = get_plugin(plugin_name)
  if plugin and plugin.PRIORITY then
    return true, plugin.schema
  end

  return false, "no plugin found"
end


function plugin_servers.start()
  if ngx.worker.id() ~= 0 then
    kong.log.notice("only worker #0 can manage")
    return
  end

  local pluginserver_timer = proc_mgmt.pluginserver_timer

  for i, server_def in ipairs(proc_mgmt.get_server_defs()) do
    if server_def.start_command then
      ngx_timer_at(0, pluginserver_timer, server_def)
    end
  end
end

return plugin_servers
