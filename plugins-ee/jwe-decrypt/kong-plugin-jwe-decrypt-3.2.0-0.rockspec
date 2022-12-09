package = "kong-plugin-jwe-decrypt"
version = "3.2.0-0"
source = {
   url = "",
   tag = "3.2.0"
}
description = {
   summary = "Decrypts a JWE Token with Kong",
   homepage = "https://docs.konghq.com/hub/kong-inc/jwe-decrypt/",
}
dependencies = {
   "lua >= 5.1",
   "lua-resty-openssl >= 0.6.2-1",
}
build = {
   type = "builtin",
   modules = {
      ["kong.plugins.jwe-decrypt.handler"] = "kong/plugins/jwe-decrypt/handler.lua",
      ["kong.plugins.jwe-decrypt.schema"] = "kong/plugins/jwe-decrypt/schema.lua",
   }
}
