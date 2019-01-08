--[[
This file is not a kong plugin; but the prototype for one.

A plugin that derives this should:
	- Implement a .new_tracer(cond) method that returns an opentracing tracer
	- The tracer must support the "http_headers" format.
	- Implement a :initialise_request(conf, ctx) method if it needs to do per-request initialisation
]]

local BasePlugin = require "kong.plugins.base_plugin"

local OpenTracingHandler = BasePlugin:extend()
OpenTracingHandler.VERSION = "scm"

-- We want to run first so that timestamps taken are at start of the phase
-- also so that other plugins might be able to use our structures
OpenTracingHandler.PRIORITY = 100000

function OpenTracingHandler:new(name)
	OpenTracingHandler.super.new(self, name or "opentracing")

	self.conf_to_tracer = setmetatable({}, {__mode = "k"})
end

function OpenTracingHandler:get_tracer(conf)
	local tracer = self.conf_to_tracer[conf]
	if tracer == nil then
		assert(self.new_tracer, "derived class must implement .new_tracer()")
		tracer = self.new_tracer(conf)
		assert(type(tracer) == "table", ".new_tracer() must return an opentracing tracer object")
		self.conf_to_tracer[conf] = tracer
	end
	return tracer
end

-- Utility function to set either ipv4 or ipv6 tags
-- nginx apis don't have a flag to indicate whether an address is v4 or v6
local function ip_tag(addr)
	-- use the presence of "." to signal v4 (v6 uses ":")
	if addr:find(".", 1, true) then
		return "peer.ipv4"
	else
		return "peer.ipv6"
	end
end

function OpenTracingHandler:initialise_request(conf, ctx)
	local tracer = self:get_tracer(conf)
	local req = kong.request
	local wire_context = tracer:extract("http_headers", req.get_headers()) -- could be nil
	local method, url
	local path_with_query = req.get_path_with_query()
	if path_with_query ~= "" then
		method = req.get_method()
		url = req.get_scheme() .. "://" .. req.get_host() .. ":"
			.. req.get_port() .. path_with_query
	end
	local forwarded_ip = kong.client.get_forwarded_ip()
	local request_span = tracer:start_span("kong.request", {
		child_of = wire_context;
		start_timestamp = ngx.req.start_time(),
		tags = {
			component = "kong";
			["span.kind"] = "server";
			["http.method"] = method;
			["http.url"] = url;
			[ip_tag(forwarded_ip)] = forwarded_ip;
			["peer.port"] = kong.client.get_forwarded_port();
		}
	})
	ctx.opentracing = {
		tracer = tracer;
		wire_context = wire_context;
		request_span = request_span;
		rewrite_span = nil;
		access_span = nil;
		proxy_span = nil;
		header_filter_span = nil;
		header_filter_finished = false;
		body_filter_span = nil;
	}
end

function OpenTracingHandler:get_context(conf, ctx)
	local opentracing = ctx.opentracing
	if not opentracing then
		self:initialise_request(conf, ctx)
		opentracing = ctx.opentracing
	end
	return opentracing
end

function OpenTracingHandler:access(conf)
	OpenTracingHandler.super.access(self, conf)

	local ctx = ngx.ctx
	local opentracing = self:get_context(conf, ctx)

	opentracing.proxy_span = opentracing.request_span:start_child_span(
		"kong.proxy",
		ctx.KONG_ACCESS_START / 1000
	)

	opentracing.access_span = opentracing.proxy_span:start_child_span(
		"kong.access",
		ctx.KONG_ACCESS_START / 1000
	)

	-- Want to send headers to upstream
	local outgoing_headers = {}
	opentracing.tracer:inject(opentracing.proxy_span, "http_headers", outgoing_headers)
	local set_header = kong.service.request.set_header
	for k, v in pairs(outgoing_headers) do
		set_header(k, v)
	end
end

function OpenTracingHandler:header_filter(conf)
	OpenTracingHandler.super.header_filter(self, conf)

	local ctx = ngx.ctx
	local opentracing = self:get_context(conf, ctx)

	local header_started = ctx.KONG_HEADER_FILTER_STARTED_AT and ctx.KONG_HEADER_FILTER_STARTED_AT / 1000 or ngx.now()

	if not opentracing.proxy_span then
		opentracing.proxy_span = opentracing.request_span:start_child_span(
			"kong.proxy",
			header_started
		)
	end

	opentracing.header_filter_span = opentracing.proxy_span:start_child_span(
		"kong.header_filter",
		header_started
	)
end

function OpenTracingHandler:body_filter(conf)
	OpenTracingHandler.super.body_filter(self, conf)

	local ctx = ngx.ctx
	local opentracing = self:get_context(conf, ctx)

	-- Finish header filter when body filter starts
	if not opentracing.header_filter_finished then
		local now = ngx.now()

		opentracing.header_filter_span:finish(now)
		opentracing.header_filter_finished = true

		opentracing.body_filter_span = opentracing.proxy_span:start_child_span("kong.body_filter", now)
	end
end

function OpenTracingHandler:log(conf)
	local now = ngx.now()

	OpenTracingHandler.super.log(self, conf)

	local ctx = ngx.ctx
	local opentracing = self:get_context(conf, ctx)
	local request_span = opentracing.request_span

	local proxy_span = opentracing.proxy_span
	if not proxy_span then
		proxy_span = request_span:start_child_span("kong.proxy", now)
		opentracing.proxy_span = proxy_span
	end
	proxy_span:set_tag("span.kind", "client")
	local proxy_end = ctx.KONG_BODY_FILTER_ENDED_AT and ctx.KONG_BODY_FILTER_ENDED_AT/1000 or now

	-- We'd run this in rewrite phase, but then we wouldn't have per-service configuration of this plugin
	if ctx.KONG_REWRITE_TIME then
		opentracing.rewrite_span = opentracing.request_span:start_child_span(
			"kong.rewrite",
			ctx.KONG_REWRITE_START / 1000
		):finish((ctx.KONG_REWRITE_START + ctx.KONG_REWRITE_TIME) / 1000)
	end

	if opentracing.access_span then
		opentracing.access_span:finish(ctx.KONG_ACCESS_ENDED_AT and ctx.KONG_ACCESS_ENDED_AT/1000 or proxy_end)
	end

	local balancer_data = ctx.balancer_data
	if balancer_data then
		local balancer_tries = balancer_data.tries
		for i=1, balancer_data.try_count do
			local try = balancer_tries[i]
			local span = proxy_span:start_child_span("kong.balancer", try.balancer_start / 1000)
			span:set_tag(ip_tag(try.ip), try.ip)
			span:set_tag("peer.port", try.port)
			span:set_tag("kong.balancer.try", i)
			if i < balancer_data.try_count then
				span:set_tag("error", true)
				span:set_tag("kong.balancer.state", try.state)
				span:set_tag("kong.balancer.code", try.code)
			end
			span:finish((try.balancer_start + try.balancer_latency) / 1000)
		end
		proxy_span:set_tag("peer.hostname", balancer_data.hostname) -- could be nil
		if balancer_data.ip ~= nil then
		   proxy_span:set_tag(ip_tag(balancer_data.ip), balancer_data.ip)
		end
		proxy_span:set_tag("peer.port", balancer_data.port)
	end

	if not opentracing.header_filter_finished and opentracing.header_filter_span then
		opentracing.header_filter_span:finish(now)
		opentracing.header_filter_finished = true
	end

	if opentracing.body_filter_span then
		opentracing.body_filter_span:finish(proxy_end)
	end

	request_span:set_tag("http.status_code", kong.response.get_status())
	if ctx.authenticated_consumer then
		request_span:set_tag("kong.consumer", ctx.authenticated_consumer.id)
	end
	if ctx.authenticated_credential then
		request_span:set_tag("kong.credential", ctx.authenticated_credential.id)
	end
	request_span:set_tag("kong.node.id", kong.node.get_id())
	if ctx.service and ctx.service.id then
		proxy_span:set_tag("kong.service", ctx.service.id)
		if ctx.route and ctx.route.id then
			proxy_span:set_tag("kong.route", ctx.route.id)
		end
		if ctx.service.name ~= ngx.null then
			proxy_span:set_tag("peer.service", ctx.service.name)
		end
	elseif ctx.api and ctx.api.id then
		proxy_span:set_tag("kong.api", ctx.api.id)
	end
	proxy_span:finish(proxy_end)
	request_span:finish(now)
end

return OpenTracingHandler
