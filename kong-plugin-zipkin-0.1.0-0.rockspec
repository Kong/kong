package = "kong-plugin-zipkin"
version = "0.1.0-0"

source = {
	url = "https://github.com/kong/kong-plugin-zipkin/archive/v0.1.0.zip";
	dir = "kong-plugin-zipkin-0.1.0";
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
	"opentracing >= 0.0.2";
}

build = {
	type = "builtin";
	modules = {
		["kong.plugins.zipkin.codec"] = "kong/plugins/zipkin/codec.lua";
		["kong.plugins.zipkin.handler"] = "kong/plugins/zipkin/handler.lua";
		["kong.plugins.zipkin.opentracing"] = "kong/plugins/zipkin/opentracing.lua";
		["kong.plugins.zipkin.random_sampler"] = "kong/plugins/zipkin/random_sampler.lua";
		["kong.plugins.zipkin.reporter"] = "kong/plugins/zipkin/reporter.lua";
		["kong.plugins.zipkin.schema"] = "kong/plugins/zipkin/schema.lua";
	};
}
