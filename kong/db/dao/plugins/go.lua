local ffi = require("ffi")
local cjson = require("cjson")
local ngx_ssl = require("ngx.ssl")
local basic_serializer = require "kong.plugins.log-serializers.basic"


local go = {}


local kong = kong
local ngx = ngx
local char_null = ffi.new("char*", ngx.null)


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

function go.bridge(op, goplugin)
  local key = L.InitBridge(op, goplugin)
  if key == -1 then
    kong.log.err("failed initializing bridge for ", goplugin)
    return
  end

  local msg = "run"
  while true do
    local ptr = L.Bridge(key, msg)
    local cmdarg = ffi.string(ptr)
    ffi.C.free(ptr)

    local c = string.find(cmdarg, ":", 1, true)
    local cmd = cmdarg
    local arg
    if c then
      cmd = cmdarg:sub(1, c - 1)
      arg = cmdarg:sub(c + 1)
    end

    if cmd == "kong.client.get_credential" then
      msg = encode(kong.client.get_credential())

    elseif cmd == "kong.client.get_consumer" then
      msg = encode(kong.client.get_consumer())

    elseif cmd == "kong.log.err" then
      kong.log.err(arg)
      msg = "ok"

    elseif cmd == "kong.log.serialize" then
      msg = cjson.encode(basic_serializer.serialize(ngx))

    elseif cmd == "kong.nginx.get_var" then
      msg = encode(ngx.var[arg])

    elseif cmd == "kong.nginx.get_tls1_version_str" then
      msg = encode(ngx_ssl.get_tls1_version_str())

    elseif cmd == "kong.nginx.get_ctx" then
      msg = encode(ngx.ctx[arg])

    elseif cmd == "kong.nginx.req_start_time" then
      msg = tostring(ngx.req.start_time())

    elseif cmd == "kong.request.get_header" then
      msg = kong.request.get_header(arg)

    elseif cmd == "kong.request.get_method" then
      msg = kong.request.get_method()

    elseif cmd == "kong.request.get_query" then
      msg = encode(kong.request.get_query())

    elseif cmd == "kong.request.get_headers" then
      msg = encode(kong.request.get_headers())

    elseif cmd == "kong.response.set_header" then
      local args = cjson.decode(arg)
      kong.response.set_header(args[1], args[2])
      msg = "ok"

    elseif cmd == "kong.response.get_headers" then
      msg = encode(kong.response.get_headers())

    elseif cmd == "kong.response.get_status" then
      msg = tostring(kong.response.get_status())

    elseif cmd == "kong.router.get_route" then
      msg = encode(kong.router.get_route())

    elseif cmd == "kong.router.get_service" then
      msg = encode(kong.router.get_service())

    elseif cmd == "ret" then
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
