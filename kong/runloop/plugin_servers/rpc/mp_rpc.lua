local kong_global = require "kong.global"
local cjson = require "cjson.safe"
local rpc_util = require "kong.runloop.plugin_servers.rpc.util"
local _

local msgpack do
  msgpack = require "MessagePack"
  local nil_pack = msgpack.packers["nil"]
  -- let msgpack encode cjson.null
  function msgpack.packers.userdata (buffer, userdata)
    if userdata == cjson.null then
      return nil_pack(buffer)
    else
      error "pack 'userdata' is unimplemented"
    end
  end
end

local ngx = ngx
local kong = kong

local cjson_encode = cjson.encode
local mp_pack = msgpack.pack
local mp_unpacker = msgpack.unpacker
local str_find = string.find


local Rpc = {}
Rpc.__index = Rpc

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

--- fix_mmap(t) : preprocess complex maps
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

local function fix_raw(bin)
  local function mp_raw(buffer)
    msgpack.packers['binary'](buffer, bin)
  end
  return mp_raw
end

local must_fix = {
  ["kong.request.get_query"] = fix_mmap,
  ["kong.request.get_headers"] = fix_mmap,
  ["kong.response.get_headers"] = fix_mmap,
  ["kong.service.response.get_headers"] = fix_mmap,
  ["kong.request.get_raw_body"] = fix_raw,
  ["kong.response.get_raw_body"] = fix_raw,
  ["kong.service.response.get_raw_body"] = fix_raw,
}

-- for unit-testing purposes only
Rpc.must_fix = must_fix


--[[

Kong API exposed to external plugins

--]]


local get_field
do
  local method_cache = {}

  function get_field(pdk, method)
    if method_cache[method] then
      return method_cache[method]

    else
      method_cache[method] = rpc_util.index_table(pdk, method)
      return method_cache[method]
    end
  end
end


local function call_pdk_method(pdk, cmd, args)
  local method = get_field(pdk, cmd)
  if not method then
    kong.log.err("could not find pdk method: ", cmd)
    return
  end

  local saved = pdk.get_saved_req_data()
  if saved and saved.plugin_name then
    kong_global.set_namespaced_log(kong, saved.plugin_name)
  end

  local ret
  if type(args) == "table" then
    ret = method(unpack(args))
  else
    ret = method(args)
  end

  local fix = must_fix[cmd]
  if fix then
    ret = fix(ret)
  end

  return ret
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




function Rpc:call(method, ...)
  self.msg_id = self.msg_id + 1
  local msg_id = self.msg_id

  local c, err = ngx.socket.connect("unix:" .. self.plugin.server_def.socket)
  if not c then
    kong.log.err("trying to connect: ", err)
    return nil, err
  end

  -- request: [ 0, msg_id, method, args ]
  local bytes, err = c:send(mp_pack({0, msg_id, method, {...}}))
  if not bytes then
    c:setkeepalive()
    return nil, err
  end

  local reader = mp_unpacker(function()
    return c:receiveany(4096)
  end)

  while true do
    -- read an MP object
    local ok, data = reader()
    if not ok then
      c:setkeepalive()
      return nil, "no data"
    end

    if data[1] == 2 then
      -- notification: [ 2, label, args ]
      self:notification(data[2], data[3])

    else
      -- response: [ 1, msg_id, error, result ]
      assert(data[1] == 1, "RPC response expected from Go plugin server")
      assert(data[2] == msg_id,
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


function Rpc:call_start_instance(plugin_name, conf)
  local status, err = self:call("plugin.StartInstance", {
    Name = plugin_name,
    Config = cjson_encode(conf)
  })

  if status == nil then
    return nil, err
  end

  return {
    id = status.Id,
    conf = conf,
    seq = conf.__seq__,
    Config = status.Config,
    rpc = self,
  }
end


function Rpc:call_close_instance(instance_id)
  return self:call("plugin.CloseInstance", instance_id)
end



function Rpc:notification(label, args)
  local f = self.plugin.rpc_notifications[label]
  if f then
    f(self, args)
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
      instance_rpc.plugin.exposed_api,
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


function Rpc:handle_event(conf, phase)
  local plugin_name = self.plugin.name

  local instance_id, err = self.plugin.instance_callbacks.get_instance_id(self.plugin, conf)
  if not err then
    _, err = bridge_loop(self, instance_id, phase)
  end

  if err then
    local err_lowered = err:lower()

    if str_find(err_lowered, "no plugin instance") then
      self.plugin.instance_callbacks.reset_instance(plugin_name, conf)
      kong.log.warn(err)
      return self:handle_event(conf, phase)
    end

    kong.log.err(err)
  end
end

local function new(plugin)
  local self = setmetatable({
    msg_id = 0,
    plugin = plugin,
  }, Rpc)
  return self
end


return {
  new = new,
}
