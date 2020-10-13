package = "kong-plugin-acme"
version = "0.2.12-1"
source = {
   url = "git+https://github.com/Kong/kong-plugin-acme.git",
   tag = "0.2.12",
}
description = {
   homepage = "https://github.com/Kong/kong-plugin-acme",
   summary = "Let's Encrypt integration with Kong",
   license = "Apache 2.0",
}
build = {
   type = "builtin",
   modules = {
      ["kong.plugins.acme.api"] = "kong/plugins/acme/api.lua",
      ["kong.plugins.acme.client"] = "kong/plugins/acme/client.lua",
      ["kong.plugins.acme.daos"] = "kong/plugins/acme/daos.lua",
      ["kong.plugins.acme.handler"] = "kong/plugins/acme/handler.lua",
      ["kong.plugins.acme.migrations.000_base_acme"] = "kong/plugins/acme/migrations/000_base_acme.lua",
      ["kong.plugins.acme.migrations.init"] = "kong/plugins/acme/migrations/init.lua",
      ["kong.plugins.acme.schema"] = "kong/plugins/acme/schema.lua",
      ["kong.plugins.acme.storage.kong"] = "kong/plugins/acme/storage/kong.lua"
   }
}
dependencies = {
  --"kong >= 1.2.0",
  "lua-resty-acme ~> 0.5"
}
