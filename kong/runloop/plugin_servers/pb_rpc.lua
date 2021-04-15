local kong_global = require "kong.global"
local cjson = require "cjson.safe"
local protoc = require "protoc"
local pb = require "pb"
require "lua_pack"

local ngx = ngx
local kong = kong


local cjson_encode = cjson.encode
local t_unpack = table.unpack       -- luacheck: ignore table
local st_pack = string.pack         -- luacheck: ignore string
local st_unpack = string.unpack     -- luacheck: ignore string

local Rpc = {}
Rpc.__index = Rpc


local pb_unwrap
do
  local structpb_value, structpb_list, structpb_struct

  function structpb_value(v)
    if v.list_value then
      return structpb_list(v.list_value)
    end

    if v.struct_value then
      return structpb_struct(v.struct_value)
    end

    return v.bool_value or v.string_value or v.number_value or v.null_value
  end

  function structpb_list(l)
    local out = {}
    for i, v in ipairs(l.values or l) do
      out[i] = structpb_value(v)
    end
    return out
  end

  function structpb_struct(v)
    return v.fields or v
  end

  local function unwrap_val(d) return d.v end

  pb_unwrap = {
    [".google.protobuf.Empty"] = function() end,
    [".google.protobuf.Value"] = structpb_value,
    [".google.protobuf.ListValue"] = function(v)
      return t_unpack(structpb_list(v))
    end,
    [".google.protobuf.Struct"] = structpb_struct,

    [".kong_plugin_protocol.Bool"] = unwrap_val,
    [".kong_plugin_protocol.Number"] = unwrap_val,
    [".kong_plugin_protocol.Int"] = unwrap_val,
    [".kong_plugin_protocol.String"] = unwrap_val,
    [".kong_plugin_protocol.KV"] = function(d)
      return d.k, structpb_value(d.v)
    end,
    [".kong_plugin_protocol.Target"] = function(d)
      return d.host, d.port
    end,
    [".kong_plugin_protocol.ExitArgs"] = function (d)
      return d.status, d.body, structpb_struct(d.headers)
    end,
  }
end

local pb_wrap
do
  local structpb_value, structpb_list, structpb_struct

  function structpb_value(v)
    local t = type(v)

    local bool_v = nil
    if t == "boolean" then
      bool_v = v
    end

    local list_v = nil
    local struct_v = nil

    if t == "table" then
      if t[1] ~= nil then
        list_v = structpb_list(v)
      else
        struct_v = structpb_struct(v)
      end
    end

    return {
      null_value = t == "nil" or nil,
      bool_value = bool_v,
      number_value = t == "number" and v or nil,
      string_value = t == "string" and v or nil,
      list_value = list_v,
      struct_value = struct_v,
    }
  end

  function structpb_list(l)
    local out = {}
    for i, v in ipairs(l) do
      out[i] = structpb_value(v)
    end
    return { values = out }
  end

  function structpb_struct(d)
    local out = {}
    for k, v in pairs(d) do
      out[k] = structpb_value(v)
    end
    return { fields = out }
  end

  local function wrap_val(v) return { v = v } end

  pb_wrap = {
    [".google.protobuf.Value"] = structpb_value,
    [".google.protobuf.ListValue"] = structpb_list,
    [".google.protobuf.Struct"] = structpb_struct,

    [".kong_plugin_protocol.Bool"] = wrap_val,
    [".kong_plugin_protocol.Number"] = wrap_val,
    [".kong_plugin_protocol.Int"] = wrap_val,
    [".kong_plugin_protocol.String"] = wrap_val,
    --[".kong_plugin_protocol.MemoryStats"] = - function(v)
    --  return {
    --    lua_shared_dicts = {
    --
    --    }
    --  }
    --end
  }
end


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

local function load_service()
  local p = protoc.new()
  --p:loadfile("kong/pluginsocket.proto")

  p:addpath("/usr/include")
  p:addpath("/usr/local/opt/protobuf/include/")

  p:addpath("/usr/local/kong/lib/")
  p:addpath("kong")

  local parsed = p:parsefile("pluginsocket.proto")

  local service = {}
  for i, s in ipairs(parsed.service) do
    for j, m in ipairs(s.method) do
      local method_name = s.name .. '.' .. m.name
      local lower_name = m.options and m.options.options and m.options.options.MethodName
          or method_name
                :gsub('_', '.')
                :gsub('([a-z]%d*)([A-Z])', '%1_%2')
                :lower()

      service[lower_name] = {
        method_name = method_name,
        method = index_table(Rpc.exposed_api, lower_name),
        input_type = m.input_type,
        output_type = m.output_type,
      }
      --print(("service[%q] = %s"):format(lower_name, pp(service[lower_name])))
    end
  end

  p:loadfile("google/protobuf/empty.proto")
  p:loadfile("google/protobuf/struct.proto")
  p:loadfile("pluginsocket.proto")

  return service
end



local rpc_service


local function identity_function(x)
  return x
end


local function call_pdk(method_name, arg)
  local method = rpc_service[method_name]
  if not method then
    return nil, ("method %q not found"):format(method_name)
  end

  local saved = Rpc.save_for_later[coroutine.running()]
  if saved and saved.plugin_name then
    kong_global.set_namespaced_log(kong, saved.plugin_name)
  end

  arg = assert(pb.decode(method.input_type, arg))
  local unwrap = pb_unwrap[method.input_type] or identity_function
  local wrap = pb_wrap[method.output_type] or identity_function

  local reply = wrap(method.method(unwrap(arg)))
  if reply == nil then
    --kong.log.debug("no reply")
    return ""
  end

  reply = assert(pb.encode(method.output_type, reply))

  return reply
end


local function read_frame(c)
  --kong.log.debug("reading frame...")
  local msg, err = c:receive(4)   -- uint32
  if not msg then
    return nil, err
  end
  local _, msg_len = st_unpack(msg, "I")
  --kong.log.debug("len: ", msg_len)

  msg, err = c:receive(msg_len)
  if not msg then
    return nil, err
  end
  --kong.log.debug(("data: %q"):format(msg))

  return msg, nil
end

local function write_frame(c, msg)
  assert (c:send(st_pack("I", #msg)))
  assert (c:send(msg))
end

function Rpc.new(socket_path, notifications)

  if not rpc_service then
    rpc_service = load_service()
  end

  --kong.log.debug("pb_rpc.new: ", socket_path)
  return setmetatable({
    socket_path = socket_path,
    msg_id = 0,
    notifications_callbacks = notifications,
  }, Rpc)
end


function Rpc:call(method, data, do_bridge_loop)
  self.msg_id = self.msg_id + 1
  local msg_id = self.msg_id
  local c = assert(ngx.socket.connect("unix:" .. self.socket_path))

  msg_id = msg_id + 1
  --kong.log.debug("will encode: ", pp{sequence = msg_id, [method] = data})
  local msg, err = assert(pb.encode(".kong_plugin_protocol.RpcCall", {      -- luacheck: ignore err
    sequence = msg_id,
    [method] = data,
  }))
  --kong.log.debug("encoded len: ", #msg)
  assert (c:send(st_pack("I", #msg)))
  assert (c:send(msg))

  while do_bridge_loop do
    local method_name
    method_name, err = read_frame(c)
    if not method_name then
      return nil, err
    end
    if method_name == "" then
      break
    end

    --kong.log.debug(("pdk method: %q (%d)"):format(method_name, #method_name))

    local args
    args, err = read_frame(c)
    if not args then
      return nil, err
    end

    local reply
    reply, err = call_pdk(method_name, args)
    if not reply then
      return nil, err
    end

    err = write_frame(c, reply)
    if err then
      return nil, err
    end
  end

  msg, err = read_frame(c)
  if not msg then
    return nil, err
  end
  c:setkeepalive()

  msg = assert(pb.decode(".kong_plugin_protocol.RpcReturn", msg))
  --kong.log.debug("decoded: "..pp(msg))
  assert(msg.sequence == msg_id)

  return msg
end


function Rpc:call_start_instance(plugin_name, conf)
  local status, err = self:call("cmd_start_instance", {
    name = plugin_name,
    config = cjson_encode(conf)
  })

  if status == nil then
    return err
  end

  return {
    id = status.instance_status.instance_id,
    conf = conf,
    seq = conf.__seq__,
    Config = status.instance_status.config,
    rpc = self,
  }
end

function Rpc:call_close_instance(instance_id)
  return self:call("cmd_close_instance", {
    instance_id = instance_id,
  })
end



function Rpc:handle_event(plugin_name, conf, phase)
  local instance_id = self.get_instance_id(plugin_name, conf)

  local res, err = self:call("cmd_handle_event", {
    instance_id = instance_id,
    event_name = phase,
  }, true)
  if not res then
    kong.log.err(err)

    if string.match(err, "No plugin instance") then
      self.reset_instance(plugin_name, conf)
      return self:handle_event(plugin_name, conf, phase)
    end
  end
end


return Rpc
