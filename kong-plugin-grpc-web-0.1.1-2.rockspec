package = "kong-plugin-grpc-web"

version = "0.1.1-2"

supported_platforms = {"linux", "macosx"}

source = {
  url = "git+https://git@github.com/Kong/kong-plugin-grpc-web.git",
  tag = "v0.1.1",
}

description = {
  summary = "gRPC-Web gateway for Kong.",
  detailed = "A Kong plugin to allow access to a gRPC service via the gRPC-Web protocol.  Primarily, this means JS browser apps using the gRPC-Web library.",
  homepage = "https://github.com/Kong/kong-plugin-grpc-web",
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
    ["kong.plugins.grpc-web.deco"] = "kong/plugins/grpc-web/deco.lua",
    ["kong.plugins.grpc-web.handler"] = "kong/plugins/grpc-web/handler.lua",
    ["kong.plugins.grpc-web.schema"] = "kong/plugins/grpc-web/schema.lua",
  }
}
