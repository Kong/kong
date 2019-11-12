local ffi = require("ffi")
local cjson = require("cjson.safe")
local ngx_ssl = require("ngx.ssl")
local basic_serializer = require "kong.plugins.log-serializers.basic"


local go = {}


local kong = kong
local ngx = ngx
local char_null = ffi.new("char*", ngx.null)
local find = string.find
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


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


local function set_plugin_conf(plugin_name, config)
  local configstr = cjson_encode(config)

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


local method_cache = new_tab(0, 50)
local function get_field(method)
  if method_cache[method] then
    return method_cache[method]

  else
    method_cache[method] = index_table(_G, method)
    return method_cache[method]
  end
end


function go.unmarshal_pdk_call(call)
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


function go.marshal_pdk_response(res, err)
  local res, err = cjson_encode({ res = res, err = err })
  if not res then
    return nil, err
  end

  return res
end


function go.call_pdk_method(cmd, args)
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

    res, err = method(unpack(args))
  end

  return res, err
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

    local method, args = go.unmarshal_pdk_call(pdk_call)
    if method  == "ret" then
      break
    end

    local pdk_res, pdk_err = go.call_pdk_method(method, args)

    local err
    msg, err = go.marshal_pdk_response(pdk_res, pdk_err)
    if not msg then
      kong.log.err("failed encoding response: ", err)
      break
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
