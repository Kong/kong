local new_tracer = require "opentracing.tracer".new
local zipkin_codec = require "kong.plugins.zipkin.codec"
local new_random_sampler = require "kong.plugins.zipkin.random_sampler".new
local new_zipkin_reporter = require "kong.plugins.zipkin.reporter".new
local OpenTracingHandler = require "kong.plugins.zipkin.opentracing"

-- Zipkin plugin derives from general opentracing one
local ZipkinLogHandler = OpenTracingHandler:extend()
ZipkinLogHandler.VERSION = "0.0.1"

function ZipkinLogHandler:new_tracer(conf)
	local tracer = new_tracer(new_zipkin_reporter(conf), new_random_sampler(conf))
	tracer:register_injector("http_headers", zipkin_codec.new_injector())
	local function warn(str)
		ngx.log(ngx.WARN, "[", self._name, "] ", str)
	end
	tracer:register_extractor("http_headers", zipkin_codec.new_extractor(warn))
	return tracer
end

local function log(premature, reporter, name)
	if premature then
		return
	end

	local ok, err = reporter:flush()
	if not ok then
		ngx.log(ngx.ERR, "[", name, "] reporter flush ", err)
		return
	end
end

function ZipkinLogHandler:log(conf)
	ZipkinLogHandler.super.log(self, conf)

	local tracer = self:get_tracer(conf)
	local zipkin_reporter = tracer.reporter -- XXX: not guaranteed by opentracing-lua?
	local ok, err = ngx.timer.at(0, log, zipkin_reporter, self._name)
	if not ok then
		ngx.log(ngx.ERR, "[", self._name, "] failed to create timer: ", err)
	end
end

return ZipkinLogHandler
