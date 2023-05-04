package = "kong-plugin-tls-metadata-headers"
version = "3.4.0-0"

source = {
  url = "",
  tag = "3.4.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "TLS Metadata Headers plugin for Kong",
  license = "Apache 2.0",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.tls-metadata-headers.handler"] = "kong/plugins/tls-metadata-headers/handler.lua",
    ["kong.plugins.tls-metadata-headers.schema"] = "kong/plugins/tls-metadata-headers/schema.lua",
  }
}
