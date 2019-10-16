local ffi = require("ffi")
local cjson = require("cjson")
local ngx_ssl = require("ngx.ssl")
local basic_serializer = require "kong.plugins.log-serializers.basic"


local go = {}


local kong = kong
local ngx = ngx
local char_null = ffi.new("char*", ngx.null)
local find = string.find


local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function() return {} end
  end
end


local init_bridge, L
do
  local bridge_initialized = false

  init_bridge = function()
    if bridge_initialized then
      return
    end

    -- has to export (some?) symbols to be able to load plugins
    L = assert(ffi.load("libkong-go-runtime.so", true))

    ffi.cdef [[
      void Init(const char* pluginDir);
      void SetConf(const char* pluginName, const char* config, int configLen);
      int64_t InitBridge(const char* op, const char* pluginName);
      char* Bridge(uint64_t key, const char* msg);
      char* GetPhases(const char* pluginName);
      char* GetVersion(const char* pluginName);
      char* GetSchema(const char* pluginName);
      int GetPriority(const char* pluginName);
    ]]

    L.Init(kong.configuration.go_plugins_dir)

    bridge_initialized = true
  end
end


local function encode(v)
  local tv = type(v)
  if tv == "string" then
    return string.format("%q", v)
  elseif tv == "number" or tv == "boolean" then
    return tostring(v)
  elseif tv == "table" then
    return cjson.encode(v)
  end
  return "null"
end

local function set_plugin_conf(plugin_name, config)
  local configstr = cjson.encode(config)

  local key = L.SetConf(plugin_name, configstr, #configstr)
  if key == -1 then
    kong.log.err("failed configuring plugin ", plugin_name)
    return
  end
end


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


local pdk_cache = new_tab(0, 50)
local function get_field(method)
  if pdk_cache[method] then
    return pdk_cache[method]
  else
    pdk_cache[method] = index_table(_G, method)
    return pdk_cache[method]
  end
end


local function unmarshal_pdk_call(call)
  local idx = find(call, ":", 1, true)

  if not idx then
    return call
  end

  local cmd = call:sub(1, idx - 1)
  local args = cjson.decode(call:sub(idx + 1))

  if args == ngx.null then
    args = {}
  end

  return cmd, args
end


function go.bridge(op, goplugin)
  local key = L.InitBridge(op, goplugin)
  if key == -1 then
    kong.log.err("failed initializing bridge for ", goplugin)
    return
  end

  local msg = "run"

  while true do
    local ptr = L.Bridge(key, msg)
    local pdk_call = ffi.string(ptr)
    ffi.C.free(ptr)

    local cmd, args = unmarshal_pdk_call(pdk_call)

    if cmd == "ret" then
      break

    elseif cmd == "kong.log.serialize" then
      msg = cjson.encode(basic_serializer.serialize(ngx))

    --
    -- ngx API
    --
    elseif cmd == "kong.nginx.get_var" then
      msg = encode(ngx.var[arg])

    elseif cmd == "kong.nginx.get_tls1_version_str" then
      msg = encode(ngx_ssl.get_tls1_version_str())

    elseif cmd == "kong.nginx.get_ctx" then
      msg = encode(ngx.ctx[arg])

    elseif cmd == "kong.nginx.req_start_time" then
      msg = encode(ngx.req.start_time())

    -- PDK
    else
      local method = get_field(cmd)
      if not method then
        kong.log.err("could not find pdk method: ", cmd)
        break
      end

      local err
      msg, err = method(unpack(args))
      if not msg and not err then
        msg = "ok"
      else
        msg = encode(msg)
      end
    end
  end
end


-- @tparam string plugin_name name of the plugin
-- @treturn table|(nil,string) the handler module table, or nil and an error message
function go.load_plugin(plugin_name)
  init_bridge()

  local phases_ptr = L.GetPhases(plugin_name)
  if phases_ptr == nil or phases_ptr == ngx.null then
    ngx.log(ngx.DEBUG, "fail")
    return nil, "Go plugin not found: " .. plugin_name
  end
  local phases = ffi.string(phases_ptr)
  ffi.C.free(phases_ptr)

  local priority = L.GetPriority(plugin_name)

  local version = "0.0.1"
  local version_ptr = L.GetVersion(plugin_name)
  if version_ptr ~= char_null then
    version = ffi.string(version_ptr)
    ffi.C.free(version_ptr)
  end

  local handler = {
    PRIORITY = priority,
    VERSION = version,
  }

  for phase in phases:gmatch("[^,]+") do
    local prev_seq = -1
    handler[phase] = function(self, conf)
      if conf.__seq__ ~= prev_seq then
        ngx.log(ngx.DEBUG, "new config, setting")
        set_plugin_conf(plugin_name, conf)
        prev_seq = conf.__seq__
      end
      go.bridge(phase, plugin_name)
    end
  end

  return true, handler
end


local schemas = {}


-- @tparam string plugin_name name of the plugin
-- @treturn table|(nil,string) the schema module table, or nil and an error message
function go.load_schema(plugin_name)
  init_bridge()

  if schemas[plugin_name] then
    return true, schemas[plugin_name]
  end

  local schema_ptr = L.GetSchema(plugin_name)
  if schema_ptr == nil then
    return nil, "Go plugin failed to return schema: " .. plugin_name
  end
  local schema_json = ffi.string(schema_ptr)
  ffi.C.free(schema_ptr)

  local schema = cjson.decode(schema_json)

  schemas[plugin_name] = schema
  return schema ~= nil, schema
end


return go
