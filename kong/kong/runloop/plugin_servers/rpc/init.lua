local protocol_implementations = {
  ["MsgPack:1"] = "kong.runloop.plugin_servers.rpc.mp_rpc",
  ["ProtoBuf:1"] = "kong.runloop.plugin_servers.rpc.pb_rpc",
}

local function new(plugin)
  local rpc_modname = protocol_implementations[plugin.server_def.protocol]
  if not rpc_modname then
    return nil, "unknown protocol implementation: " .. (plugin.server_def.protocol or "nil")
  end

  kong.log.notice("[pluginserver] loading protocol ", plugin.server_def.protocol, " for plugin ", plugin.name)

  local rpc_mod = require (rpc_modname)
  local rpc = rpc_mod.new(plugin)

  return rpc
end

return {
  new = new,
}
