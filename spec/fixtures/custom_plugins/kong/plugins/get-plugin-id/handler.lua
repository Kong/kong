local PluginConfigDumpHandler =  {
  VERSION = "1.0.0",
  PRIORITY = 1,
}

function PluginConfigDumpHandler:access(conf)
  kong.response.exit(200, kong.plugin.get_id())
end

return PluginConfigDumpHandler
