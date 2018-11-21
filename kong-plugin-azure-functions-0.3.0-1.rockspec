package = "kong-plugin-azure-functions"
version = "0.3.0-1"
source = {
  url = "git://github.com/kong/kong-plugin-azure-functions",
  tag = "0.3.0"
}
description = {
  summary = "This plugin allows Kong to invoke Azure functions.",
  license = "Apache 2.0"
}
dependencies = {
  "lua >= 5.1",
  --"kong >= 0.15.0",
}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.azure-functions.handler"] = "kong/plugins/azure-functions/handler.lua",
    ["kong.plugins.azure-functions.schema"]  = "kong/plugins/azure-functions/schema.lua",
  }
}
