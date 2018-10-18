local to_hex = require "resty.string".to_hex
local new_span_context = require "opentracing.span_context".new

local function hex_to_char(c)
	return string.char(tonumber(c, 16))
end

local function from_hex(str)
	if str ~= nil then -- allow nil to pass through
		str = str:gsub("%x%x", hex_to_char)
	end
	return str
end

local function new_extractor(warn)
	return function(headers)
		-- X-B3-Sampled: if an upstream decided to sample this request, we do too.
		local sample = headers["x-b3-sampled"]
		if sample == "1" or sample == "true" then
			sample = true
		elseif sample == "0" or sample == "false" then
			sample = false
		elseif sample ~= nil then
			warn("x-b3-sampled header invalid; ignoring.")
			sample = nil
		end

		-- X-B3-Flags: if it equals '1' then it overrides sampling policy
		-- We still want to warn on invalid sample header, so do this after the above
		local debug = headers["x-b3-flags"]
		if debug == "1" then
			sample = true
		elseif debug ~= nil then
			warn("x-b3-flags header invalid; ignoring.")
		end

		local had_invalid_id = false

		local trace_id = headers["x-b3-traceid"]
		-- Validate trace id
		if trace_id and ((#trace_id ~= 16 and #trace_id ~= 32) or trace_id:match("%X")) then
			warn("x-b3-traceid header invalid; ignoring.")
			had_invalid_id = true
		end

		local parent_span_id = headers["x-b3-parentspanid"]
		-- Validate parent_span_id
		if parent_span_id and (#parent_span_id ~= 16 or parent_span_id:match("%X")) then
			warn("x-b3-parentspanid header invalid; ignoring.")
			had_invalid_id = true
		end

		local request_span_id = headers["x-b3-spanid"]
		-- Validate request_span_id
		if request_span_id and (#request_span_id ~= 16 or request_span_id:match("%X")) then
			warn("x-b3-spanid header invalid; ignoring.")
			had_invalid_id = true
		end

		if trace_id == nil or had_invalid_id then
			return nil
		end

		-- Process jaegar baggage header
		local baggage = {}
		for k, v in pairs(headers) do
			local baggage_key = k:match("^uberctx%-(.*)$")
			if baggage_key then
				baggage[baggage_key] = ngx.unescape_uri(v)
			end
		end

		trace_id = from_hex(trace_id)
		parent_span_id = from_hex(parent_span_id)
		request_span_id = from_hex(request_span_id)

		return new_span_context(trace_id, request_span_id, parent_span_id, sample, baggage)
	end
end

local function new_injector()
	return function(span_context, headers)
		-- We want to remove headers if already present
		headers["x-b3-traceid"] = to_hex(span_context.trace_id)
		headers["x-b3-parentspanid"] = span_context.parent_id and to_hex(span_context.parent_id) or nil
		headers["x-b3-spanid"] = to_hex(span_context.span_id)
		local Flags = kong.request.get_header("x-b3-flags") -- Get from request headers
		headers["x-b3-flags"] = Flags
		headers["x-b3-sampled"] = (not Flags) and (span_context.should_sample and "1" or "0") or nil
		for key, value in span_context:each_baggage_item() do
			-- XXX: https://github.com/opentracing/specification/issues/117
			headers["uberctx-"..key] = ngx.escape_uri(value)
		end
	end
end

return {
	new_extractor = new_extractor;
	new_injector = new_injector;
}
