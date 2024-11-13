-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
