package = "kong-plugin-letsencrypt"
version = "dev-1"
source = {
   url = "git+https://github.com/Kong/kong-plugin-letsencrypt.git"
}
description = {
   homepage = "https://github.com/Kong/kong-plugin-letsencrypt",
   summary = "Let's Encrypt integration with Kong",
   license = "Apache 2.0",
}
build = {
   type = "builtin",
   modules = {
      ["kong.plugins.letsencrypt.client"] = "kong/plugins/letsencrypt/client.lua",
      ["kong.plugins.letsencrypt.daos"] = "kong/plugins/letsencrypt/daos.lua",
      ["kong.plugins.letsencrypt.handler"] = "kong/plugins/letsencrypt/handler.lua",
      ["kong.plugins.letsencrypt.migrations.000_base_letsencrypt"] = "kong/plugins/letsencrypt/migrations/000_base_letsencrypt.lua",
      ["kong.plugins.letsencrypt.migrations.init"] = "kong/plugins/letsencrypt/migrations/init.lua",
      ["kong.plugins.letsencrypt.schema"] = "kong/plugins/letsencrypt/schema.lua",
      ["kong.plugins.letsencrypt.storage.kong"] = "kong/plugins/letsencrypt/storage/kong.lua"
   }
}
dependencies = {
  --"kong >= 1.2.0",
  "lua-resty-acme >= 0.3.0"
}
