package = "kong-plugin-enterprise-oauth2-introspection"
version = "3.2.0-0"
source = {
  url = "git://github.com/kong/kong-plugin-enterprise-oauth2-introspection",
  tag = "3.2.0"
}
description = {
  summary = "A Kong plugin for authenticating tokens using as third party OAuth 2.0 Introspection Endpoint",
}
dependencies = {
  "lua >= 5.1"
}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.oauth2-introspection.handler"] = "kong/plugins/oauth2-introspection/handler.lua",
    ["kong.plugins.oauth2-introspection.schema"] = "kong/plugins/oauth2-introspection/schema.lua",
  }
}
