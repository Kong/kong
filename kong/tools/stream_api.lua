
require "lua_pack"


local kong       = kong
local st_pack    = string.pack      -- luacheck: ignore string
local st_unpack  = string.unpack    -- luacheck: ignore string
local st_format  = string.format

local PREFIX = ngx.config.prefix()

local stream_api = {}

local _handlers  = {}


function stream_api.load_handlers()
  local utils = require "kong.tools.utils"

  for plugin_name in pairs(kong.configuration.loaded_plugins) do
    local loaded, custom_endpoints = utils.load_module_if_exists("kong.plugins." .. plugin_name .. ".api")
    if loaded and custom_endpoints._stream then
      ngx.log(ngx.DEBUG, "Register stream api for plugin: ", plugin_name)
      _handlers[plugin_name] = custom_endpoints._stream
      custom_endpoints._stream = nil
    end
  end
end

function stream_api.request(key, data, socket_path)
  local socket = assert(ngx.socket.udp())
  assert(socket:setpeername(socket_path or "unix:" .. PREFIX .. "/stream_rpc.sock"))

  local ok, err = socket:send(st_pack("=PP", key, data))
  if not ok then
    socket:close()
    return ok, err
  end

  data, err = socket:receive()
  if not data then
    socket:close()
    return data, err
  end

  local _, status, payload = st_unpack(data, "=SP")
  if status == 0 then
    socket:close()
    return nil, payload
  end

  socket:close()
  return payload
end


function stream_api.handle()

  local socket = ngx.req.socket()
  local data, err = socket:receive()
  if not data then
    kong.log.error(err)
    return
  end

  local _, key, payload = st_unpack(data, "=PP")

  local f = _handlers[key]
  if not f then
    socket:send(st_pack("=SP", 0, "no handler"))
    return
  end

  local res
  res, err = f(payload)
  if not res then
    kong.log.error(st_format("stream_api handler %q returned error: %q", key, err))
    socket:send(st_pack("=SP", 0, tostring(err)))
    return
  end

  socket:send(st_pack("=SP", 1, tostring(res)))
end


return stream_api
