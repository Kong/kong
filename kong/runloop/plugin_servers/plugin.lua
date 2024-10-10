local cjson = require "cjson.safe"
local ngx_ssl = require "ngx.ssl"
local clone = require "table.clone"
local rpc = require "kong.runloop.plugin_servers.rpc"

local type = type
local ngx_sleep = ngx.sleep
local ngx_var = ngx.var
local cjson_encode = cjson.encode
local ipairs = ipairs
local coroutine_running = coroutine.running
local get_ctx_table = require("resty.core.ctx").get_ctx_table
local native_timer_at = _G.native_timer_at or ngx.timer.at

--- currently running plugin instances
local running_instances = {}

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

--- keep request data a bit longer, into the log timer
local req_data = {}

local function get_saved_req_data()
  return req_data[coroutine_running()]
end

local exposed_api = {
  kong = kong,

  get_saved_req_data = get_saved_req_data,

  ["kong.log.serialize"] = function()
    local saved = get_saved_req_data()
    return cjson_encode(saved and saved.serialize_data or kong.log.serialize())
  end,

  ["kong.nginx.get_var"] = function(v)
    return ngx_var[v]
  end,

  ["kong.nginx.get_tls1_version_str"] = ngx_ssl.get_tls1_version_str,

  ["kong.nginx.get_ctx"] = function(k)
    local saved = get_saved_req_data()
    local ngx_ctx = saved and saved.ngx_ctx or ngx.ctx
    return ngx_ctx[k]
  end,

  ["kong.nginx.set_ctx"] = function(k, v)
    local saved = get_saved_req_data()
    local ngx_ctx = saved and saved.ngx_ctx or ngx.ctx
    ngx_ctx[k] = v
  end,

  ["kong.ctx.shared.get"] = function(k)
    local saved = get_saved_req_data()
    local ctx_shared = saved and saved.ctx_shared or kong.ctx.shared
    return ctx_shared[k]
  end,

  ["kong.ctx.shared.set"] = function(k, v)
    local saved = get_saved_req_data()
    local ctx_shared = saved and saved.ctx_shared or kong.ctx.shared
    ctx_shared[k] = v
  end,

  ["kong.request.get_headers"] = function(max)
    local saved = get_saved_req_data()
    return saved and saved.request_headers or kong.request.get_headers(max)
  end,

  ["kong.request.get_header"] = function(name)
    local saved = get_saved_req_data()
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
    local saved = get_saved_req_data()
    local ngx_ctx = saved and saved.ngx_ctx or ngx.ctx
    return kong.request.get_uri_captures(ngx_ctx)
  end,

  ["kong.response.get_status"] = function()
    local saved = get_saved_req_data()
    return saved and saved.response_status or kong.response.get_status()
  end,

  ["kong.response.get_headers"] = function(max)
    local saved = get_saved_req_data()
    return saved and saved.response_headers or kong.response.get_headers(max)
  end,

  ["kong.response.get_header"] = function(name)
    local saved = get_saved_req_data()
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
    local saved = get_saved_req_data()
    return kong.response.get_source(saved and saved.ngx_ctx or nil)
  end,

  ["kong.nginx.req_start_time"] = function()
    local saved = get_saved_req_data()
    return saved and saved.req_start_time or req_start_time()
  end,
}


--- Phase closures
local function build_phases(plugin)
  if not plugin then
    return
  end

  for _, phase in ipairs(plugin.phases) do
    if phase == "log" then
      plugin[phase] = function(self, conf)
        native_timer_at(0, function(premature, saved)
          if premature then
            return
          end
          get_ctx_table(saved.ngx_ctx)
          local co = coroutine_running()
          req_data[co] = saved
          plugin.rpc:handle_event(conf, phase)
          req_data[co] = nil
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
        plugin.rpc:handle_event(conf, phase)
      end
    end
  end

  return plugin
end

--- handle notifications from pluginservers
local rpc_notifications = {}

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

local function reset_instances_for_plugin(plugin_name)
  for k, instance in pairs(running_instances) do
    if instance.plugin_name == plugin_name then
      running_instances[k] = nil
    end
  end
end

--- reset_instance: removes an instance from the table.
local function reset_instance(plugin_name, conf)
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

local get_instance_id

do
  local SLEEP_STEP = 0.1
  local WAIT_TIME = 10
  local MAX_WAIT_STEPS = WAIT_TIME / SLEEP_STEP

  --- get_instance_id: gets an ID to reference a plugin instance running in the
  --- pluginserver; each configuration of a plugin is handled by a different
  --- instance.  Biggest complexity here is due to the remote (and thus non-atomic
  --- and fallible) operation of starting the instance at the server.
  function get_instance_id(plugin, conf)
    local plugin_name = plugin.name

    local key = kong.plugin.get_id()
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

    local new_instance_info, err = plugin.rpc:call_start_instance(plugin_name, conf)
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
      plugin.rpc:call_close_instance(old_instance_id)
      -- don't care if there's an error, maybe other thread closed it first.
    end

    return instance_info.id
  end
end

--
-- instance callbacks manage the state of a plugin instance
-- - get_instance_id (which also starts and instance)
-- - reset_instance, which removes an instance from the local cache
--
local instance_callbacks = {
  reset_instance = reset_instance,
  get_instance_id = get_instance_id,
}

local function new(plugin_info)
  -- 
  -- plugin_info
  -- * name
  -- * priority
  -- * version
  -- * schema
  -- * phases
  -- * server_def
  --

  local self = build_phases(plugin_info)
  self.instance_callbacks = instance_callbacks
  self.exposed_api = exposed_api
  self.rpc_notifications = rpc_notifications

  local plugin_rpc, err = rpc.new(self)
  if not rpc then
    return nil, err
  end

  self.rpc = plugin_rpc

  return self
end


return {
  new = new,
  reset_instances_for_plugin = reset_instances_for_plugin,
}
