
local proc_mgmt = require "kong.runloop.plugin_servers.process"
local cjson = require "cjson.safe"
local clone = require "table.clone"
local ngx_ssl = require "ngx.ssl"
local SIGTERM = 15

local type = type
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber

local ngx = ngx
local kong = kong
local ngx_var = ngx.var
local ngx_sleep = ngx.sleep
local worker_id = ngx.worker.id

local coroutine_running = coroutine.running
local get_plugin_info = proc_mgmt.get_plugin_info
local get_ctx_table = require("resty.core.ctx").get_ctx_table

local cjson_encode = cjson.encode
local native_timer_at = _G.native_timer_at or ngx.timer.at

local req_start_time
local req_get_headers
local resp_get_headers

if ngx.config.subsystem == "http" then
  req_start_time   = ngx.req.start_time
  req_get_headers  = ngx.req.get_headers
  resp_get_headers = ngx.resp.get_headers

else
  local NOOP = function() end

  req_start_time   = NOOP
  req_get_headers  = NOOP
  resp_get_headers = NOOP
end

local SLEEP_STEP = 0.1
local WAIT_TIME = 10
local MAX_WAIT_STEPS = WAIT_TIME / SLEEP_STEP

--- keep request data a bit longer, into the log timer
local save_for_later = {}

--- handle notifications from pluginservers
local rpc_notifications = {}

--- currently running plugin instances
local running_instances = {}

local function get_saved()
  return save_for_later[coroutine_running()]
end

local exposed_api = {
  kong = kong,

  ["kong.log.serialize"] = function()
    local saved = get_saved()
    return cjson_encode(saved and saved.serialize_data or kong.log.serialize())
  end,

  ["kong.nginx.get_var"] = function(v)
    return ngx_var[v]
  end,

  ["kong.nginx.get_tls1_version_str"] = ngx_ssl.get_tls1_version_str,

  ["kong.nginx.get_ctx"] = function(k)
    local saved = get_saved()
    local ngx_ctx = saved and saved.ngx_ctx or ngx.ctx
    return ngx_ctx[k]
  end,

  ["kong.nginx.set_ctx"] = function(k, v)
    local saved = get_saved()
    local ngx_ctx = saved and saved.ngx_ctx or ngx.ctx
    ngx_ctx[k] = v
  end,

  ["kong.ctx.shared.get"] = function(k)
    local saved = get_saved()
    local ctx_shared = saved and saved.ctx_shared or kong.ctx.shared
    return ctx_shared[k]
  end,

  ["kong.ctx.shared.set"] = function(k, v)
    local saved = get_saved()
    local ctx_shared = saved and saved.ctx_shared or kong.ctx.shared
    ctx_shared[k] = v
  end,

  ["kong.request.get_headers"] = function(max)
    local saved = get_saved()
    return saved and saved.request_headers or kong.request.get_headers(max)
  end,

  ["kong.request.get_header"] = function(name)
    local saved = get_saved()
    if not saved then
      return kong.request.get_header(name)
    end

    local header_value = saved.request_headers[name]
    if type(header_value) == "table" then
      header_value = header_value[1]
    end

    return header_value
  end,

  ["kong.request.get_uri_captures"] = function()
    local saved = get_saved()
    local ngx_ctx = saved and saved.ngx_ctx or ngx.ctx
    return kong.request.get_uri_captures(ngx_ctx)
  end,

  ["kong.response.get_status"] = function()
    local saved = get_saved()
    return saved and saved.response_status or kong.response.get_status()
  end,

  ["kong.response.get_headers"] = function(max)
    local saved = get_saved()
    return saved and saved.response_headers or kong.response.get_headers(max)
  end,

  ["kong.response.get_header"] = function(name)
    local saved = get_saved()
    if not saved then
      return kong.response.get_header(name)
    end

    local header_value = saved.response_headers and saved.response_headers[name]
    if type(header_value) == "table" then
      header_value = header_value[1]
    end

    return header_value
  end,

  ["kong.response.get_source"] = function()
    local saved = get_saved()
    return kong.response.get_source(saved and saved.ngx_ctx or nil)
  end,

  ["kong.nginx.req_start_time"] = function()
    local saved = get_saved()
    return saved and saved.req_start_time or req_start_time()
  end,
}


local get_instance_id
local reset_instance
local reset_instances_for_plugin

local protocol_implementations = {
  ["MsgPack:1"] = "kong.runloop.plugin_servers.mp_rpc",
  ["ProtoBuf:1"] = "kong.runloop.plugin_servers.pb_rpc",
}

local function get_server_rpc(server_def)
  if not server_def.rpc then

    local rpc_modname = protocol_implementations[server_def.protocol]
    if not rpc_modname then
      kong.log.err("Unknown protocol implementation: ", server_def.protocol)
      return nil, "Unknown protocol implementation"
    end

    local rpc = require (rpc_modname)
    rpc.get_instance_id = rpc.get_instance_id or get_instance_id
    rpc.reset_instance = rpc.reset_instance or reset_instance
    rpc.save_for_later = rpc.save_for_later or save_for_later
    rpc.exposed_api = rpc.exposed_api or exposed_api

    server_def.rpc = rpc.new(server_def.socket, rpc_notifications)
  end

  return server_def.rpc
end



--- get_instance_id: gets an ID to reference a plugin instance running in a
--- pluginserver each configuration in the database is handled by a different
--- instance.  Biggest complexity here is due to the remote (and thus non-atomic
--- and fallible) operation of starting the instance at the server.
function get_instance_id(plugin_name, conf)
  local key = type(conf) == "table" and kong.plugin.get_id() or plugin_name
  local instance_info = running_instances[key]

  local wait_count = 0
  while instance_info and not instance_info.id do
    -- some other thread is already starting an instance
    -- prevent busy-waiting
    ngx_sleep(SLEEP_STEP)

    -- to prevent a potential dead loop when someone failed to release the ID
    wait_count = wait_count + 1
    if wait_count > MAX_WAIT_STEPS then
      running_instances[key] = nil
      return nil, "Could not claim instance_id for " .. plugin_name .. " (key: " .. key .. ")"
    end
    instance_info = running_instances[key]
  end

  if instance_info
    and instance_info.id
    and instance_info.seq == conf.__seq__
    and instance_info.conf and instance_info.conf.__plugin_id == key
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

  local new_instance_info, err = server_rpc:call_start_instance(plugin_name, conf)
  if new_instance_info == nil then
    kong.log.err("starting instance: ", err)
    -- remove claim, some other thread might succeed
    running_instances[key] = nil
    error(err)
  end

  instance_info.id = new_instance_info.id
  instance_info.plugin_name = plugin_name
  instance_info.conf = new_instance_info.conf
  instance_info.seq = new_instance_info.seq
  instance_info.Config = new_instance_info.Config
  instance_info.rpc = new_instance_info.rpc

  if old_instance_id then
    -- there was a previous instance with same key, close it
    server_rpc:call_close_instance(old_instance_id)
    -- don't care if there's an error, maybe other thread closed it first.
  end

  return instance_info.id
end

function reset_instances_for_plugin(plugin_name)
  for k, instance in pairs(running_instances) do
    if instance.plugin_name == plugin_name then
      running_instances[k] = nil
    end
  end
end

--- reset_instance: removes an instance from the table.
function reset_instance(plugin_name, conf)
  --
  -- the same plugin (which acts as a plugin server) is shared among
  -- instances of the plugin; for example, the same plugin can be applied
  -- to many routes
  -- `reset_instance` is called when (but not only) the plugin server died;
  -- in such case, all associated instances must be removed, not only the current
  --
  reset_instances_for_plugin(plugin_name)

  local ok, err = kong.worker_events.post("plugin_server", "reset_instances", { plugin_name = plugin_name })
  if not ok then
    kong.log.err("failed to post plugin_server reset_instances event: ", err)
  end
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





--- Phase closures
local function build_phases(plugin)
  if not plugin then
    return
  end

  local server_rpc = get_server_rpc(plugin.server_def)

  for _, phase in ipairs(plugin.phases) do
    if phase == "log" then
      plugin[phase] = function(self, conf)
        native_timer_at(0, function(premature, saved)
          if premature then
            return
          end
          get_ctx_table(saved.ngx_ctx)
          local co = coroutine_running()
          save_for_later[co] = saved
          server_rpc:handle_event(self.name, conf, phase)
          save_for_later[co] = nil
        end, {
          plugin_name = self.name,
          serialize_data = kong.log.serialize(),
          ngx_ctx = clone(ngx.ctx),
          ctx_shared = kong.ctx.shared,
          request_headers = req_get_headers(),
          response_headers = resp_get_headers(),
          response_status = ngx.status,
          req_start_time = req_start_time(),
        })
      end

    else
      plugin[phase] = function(self, conf)
        server_rpc:handle_event(self.name, conf, phase)
      end
    end
  end

  return plugin
end



--- module table
local plugin_servers = {}


local loaded_plugins = {}

local function get_plugin(plugin_name)
  kong = kong or _G.kong    -- some CLI cmds set the global after loading the module.
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
  if worker_id() ~= 0 then
    return
  end

  local pluginserver_timer = proc_mgmt.pluginserver_timer

  for _, server_def in ipairs(proc_mgmt.get_server_defs()) do
    if server_def.start_command then
      native_timer_at(0, pluginserver_timer, server_def)
    end
  end

  -- in case plugin server restarts, all workers need to update their defs
  kong.worker_events.register(function (data)
    reset_instances_for_plugin(data.plugin_name)
  end, "plugin_server", "reset_instances")
end

function plugin_servers.stop()
  if worker_id() ~= 0 then
    return
  end

  for _, server_def in ipairs(proc_mgmt.get_server_defs()) do
    if server_def.proc then
      server_def.proc:kill(SIGTERM)
    end
  end
end

return plugin_servers
