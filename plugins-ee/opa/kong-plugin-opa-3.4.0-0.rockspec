package = "kong-plugin-opa"
version = "3.4.0-0"

source = {
  url = "git://github.com/Kong/kong-plugin-opa",
  tag = "3.4.0"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Open Policy Agent integration plugin for Kong",
  license = "Apache 2.0",
}

dependencies = {
  --"kong >= 2.3.0",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.opa.handler"] = "kong/plugins/opa/handler.lua",
    ["kong.plugins.opa.schema"] = "kong/plugins/opa/schema.lua",
    ["kong.plugins.opa.decision"] = "kong/plugins/opa/decision.lua",
  }
}
