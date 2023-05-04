package = "kong-plugin-tls-handshake-modifier"
version = "3.4.0-0"

source = {
  url = "",
  tag = "3.4.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "TLS Handshake Modifier plugin for Kong",
  license = "Apache 2.0",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.tls-handshake-modifier.handler"] = "kong/plugins/tls-handshake-modifier/handler.lua",
    ["kong.plugins.tls-handshake-modifier.schema"] = "kong/plugins/tls-handshake-modifier/schema.lua",
    ["kong.plugins.tls-handshake-modifier.cache"] = "kong/plugins/tls-handshake-modifier/cache.lua",
  }
}
