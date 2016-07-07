package = "kong-custom-plugins"
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

}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.request-transformer-custom.handler"] = "kong/plugins/request-transformer-custom/handler.lua",
    ["kong.plugins.request-transformer-custom.schema"] = "kong/plugins/request-transformer-custom/schema.lua"
  }
}
