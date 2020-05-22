package = "kong-plugin-grpc-gateway"

version = "0.1.0-2"

supported_platforms = {"linux", "macosx"}

source = {
  url = "git+https://git@github.com/Kong/kong-plugin-grpc-gateway.git",
  tag = "v0.1.0",
}

description = {
  summary = "grpc-gateway gateway for Kong.",
  detailed = "A Kong plugin to allow access to a gRPC service via REST.",
  homepage = "https://github.com/Kong/kong-plugin-grpc-gateway",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
  "lua-protobuf ~> 0.3",
  "lua_pack == 1.0.5",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.grpc-gateway.deco"] = "kong/plugins/grpc-gateway/deco.lua",
    ["kong.plugins.grpc-gateway.handler"] = "kong/plugins/grpc-gateway/handler.lua",
    ["kong.plugins.grpc-gateway.schema"] = "kong/plugins/grpc-gateway/schema.lua",
  }
}
