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
    ["kong.yop.cache"] = "kong/yop/cache.lua",
    ["kong.yop.http_client"] = "kong/yop/http_client.lua",
    ["kong.yop.response"] = "kong/yop/response.lua",
    ["kong.yop.security_center"] = "kong/yop/security_center.lua",
    ["kong.plugins.yop.interceptor.auth"] = "kong/plugins/yop/interceptor/auth.lua",
    ["kong.plugins.yop.interceptor.decrypt"] = "kong/plugins/yop/interceptor/decrypt.lua",
    ["kong.plugins.yop.interceptor.http_method"] = "kong/plugins/yop/interceptor/http_method.lua",
    ["kong.plugins.yop.interceptor.initialize_ctx"] = "kong/plugins/yop/interceptor/initialize_ctx.lua",
    ["kong.plugins.yop.interceptor.request_transformer"] = "kong/plugins/yop/interceptor/request_transformer.lua",
    ["kong.plugins.yop.interceptor.request_validator"] = "kong/plugins/yop/interceptor/request_validator.lua",
    ["kong.plugins.yop.interceptor.whitelist"] = "kong/plugins/yop/interceptor/whitelist.lua",
    ["kong.plugins.yop.interceptor.default_value"] = "kong/plugins/yop/interceptor/default_value.lua",
    ["kong.plugins.yop.interceptor.prepare_stream"] = "kong/plugins/yop/interceptor/prepare_stream.lua",
    ["kong.plugins.yop.handler"] = "kong/plugins/yop/handler.lua",
    ["kong.plugins.yop.schema"] = "kong/plugins/yop/schema.lua"
    ["kong.yop.marshaller_util"] = "kong/yop/marshaller_util.lua",

  }
}
