local PluginConfigDumpHandler =  {
  VERSION = "1.0.0",
  PRIORITY = 1,
}

function PluginConfigDumpHandler:access(conf)
  kong.response.exit(200, conf)
end

return PluginConfigDumpHandler
