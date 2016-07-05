package = "kong"
version = "0.8.3-0"
supported_platforms = {"linux", "macosx"}
source = {
  url = "git://github.com/kensou97/kong",
}
description = {
  summary = "Kong is a scalable and customizable API Management Layer built on top of Nginx.",
  homepage = "http://getkong.org",
  license = "MIT"
}
dependencies = {
  "luasec ~> 0.5-2",

  "penlight ~> 1.3.2",
  "lua-resty-http ~> 0.07-0",
  "lua_uuid ~> 0.2.0-2",
  "lua_system_constants ~> 0.1.1-0",
  "luatz ~> 0.3-1",
  "yaml ~> 1.1.2-1",
  "lapis ~> 1.3.1-1",
  "stringy ~> 0.4-1",
  "lua-cassandra ~> 0.5.2",
  "pgmoon ~> 1.4.0",
  "multipart ~> 0.3-2",
  "lua-path ~> 0.2.3-1",
  "lua-cjson ~> 2.1.0-1",
  "ansicolors ~> 1.0.2-3",
  "lbase64 ~> 20120820-1",
  "lua-resty-iputils ~> 0.2.0-1",
  "mediator_lua ~> 1.1.2-0",

  "luasocket ~> 2.0.2-6",
  "lrexlib-pcre ~> 2.7.2-1",
  "lua-llthreads2 ~> 0.1.3-1",
  "luacrypto >= 0.3.2-1",
  "luasyslog >= 1.0.0-2",
  "lua_pack ~> 1.0.4-0"
}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.request-transformer-custom.handler"] = "kong/plugins/request-transformer-custom/handler.lua",
    ["kong.plugins.request-transformer-custom.schema"] = "kong/plugins/request-transformer-custom/schema.lua"
  }
}
