package = "kong-plugin-zipkin"
version = "0.2.1-1"

source = {
  url = "https://github.com/kong/kong-plugin-zipkin/archive/v0.2.1.zip";
  dir = "kong-plugin-zipkin-0.2.1";
}

description = {
  summary = "This plugin allows Kong to propagate Zipkin headers and report to a Zipkin server";
  homepage = "https://github.com/kong/kong-plugin-zipkin";
  license = "Apache 2.0";
}

dependencies = {
  "lua >= 5.1";
  "lua-cjson";
  "lua-resty-http >= 0.11";
  "luatz";
  "luaossl";
}

build = {
  type = "builtin";
  modules = {
    ["kong.plugins.zipkin.extractor"] = "kong/plugins/zipkin/extractor.lua";
    ["kong.plugins.zipkin.handler"] = "kong/plugins/zipkin/handler.lua";
    ["kong.plugins.zipkin.reporter"] = "kong/plugins/zipkin/reporter.lua";
    ["kong.plugins.zipkin.span"] = "kong/plugins/zipkin/span.lua";
    ["kong.plugins.zipkin.span_context"] = "kong/plugins/zipkin/span_context.lua";
    ["kong.plugins.zipkin.tracer"] = "kong/plugins/zipkin/tracer.lua";
    ["kong.plugins.zipkin.schema"] = "kong/plugins/zipkin/schema.lua";
  };
}
