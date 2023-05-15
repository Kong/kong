package = "kong-plugin-enterprise-exit-transformer"
version = "dev-0"

supported_platforms = {"linux", "macosx"}
source = {
  url = "http://github.com/Kong/kong-plugin-enterprise-exit-transformer.git",
  tag = "dev"
}

description = {
  summary = "Kong Enterprise Exit Transformer",
}

dependencies = {

}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.exit-transformer"] = "kong/plugins/exit-transformer/init.lua",
    ["kong.plugins.exit-transformer.handler"] = "kong/plugins/exit-transformer/handler.lua",
    ["kong.plugins.exit-transformer.schema"] = "kong/plugins/exit-transformer/schema.lua",
  }
}
