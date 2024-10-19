-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"
local str = require "resty.string"
local http = require "resty.http"

local ngx = ngx
local kong = kong
local table = table
local insert = table.insert
local to_hex = str.to_hex

local _M = {
  PRIORITY = 1001,
  VERSION = "1.0",
}

local tracer_name = "tcp-trace-exporter"

function _M:certificate(config)
  if not config.custom_spans then
    return
  end

  local tracer = kong.tracing(tracer_name)

  local span = tracer.start_span("certificate", {
    parent = kong.tracing.active_span(),
  })
  tracer.set_active_span(span)
end

function _M:rewrite(config)
  if not config.custom_spans then
    return
  end

  local tracer = kong.tracing(tracer_name)

  local span = tracer.start_span("rewrite", {
    parent = kong.tracing.active_span(),
  })
  tracer.set_active_span(span)

  -- tracing DNS!
  local httpc = http.new()
  -- Single-shot requests use the `request_uri` interface.
  local res, err = httpc:request_uri("https://konghq.com", {
    method = "GET",
  })

  if not res then
    ngx.log(ngx.ERR, "request failed: ", err)
  end
end


function _M:access(config)
  local tracer = kong.tracing(tracer_name)

  local span
  if config.custom_spans then
    span = tracer.start_span("access")
    tracer.set_active_span(span)
  end

  kong.db.routes:page()

  if span then
    span:finish()
  end
end


function _M:header_filter(config)
  local tracer = kong.tracing(tracer_name)

  local span
  if config.custom_spans then
    span = tracer.start_span("header_filter")
    tracer.set_active_span(span)
  end

  if span then
    span:finish()
  end
end


function _M:body_filter(config)
  local tracer = kong.tracing(tracer_name)

  local span
  if config.custom_spans then
    span = tracer.start_span("body_filter")
    tracer.set_active_span(span)
  end

  if span then
    span:finish()
  end
end


local function push_data(premature, data, config)
  if premature then
    return
  end

  local tcpsock = ngx.socket.tcp()
  tcpsock:settimeouts(10000, 10000, 10000)
  local ok, err = tcpsock:connect(config.host, config.port)
  if not ok then
    kong.log.err("connect err: ".. err)
    return
  end
  local _, err = tcpsock:send(data .. "\n")
  if err then
    kong.log.err(err)
  end
  tcpsock:close()
end

function _M:log(config)
  local tracer = kong.tracing(tracer_name)
  local span = tracer.active_span()

  if span then
    kong.log.debug("Exit span name: ", span.name)
    span:finish()
  end

  kong.log.debug("Total spans: ", ngx.ctx.KONG_SPANS and #ngx.ctx.KONG_SPANS)

  local spans = {}
  local process_span = function (span)
    if span.should_sample == false then
      return
    end
    local s = table.clone(span)
    s.tracer = nil
    s.parent = nil
    s.trace_id = to_hex(s.trace_id)
    s.parent_id = s.parent_id and to_hex(s.parent_id)
    s.span_id = to_hex(s.span_id)
    insert(spans, s)
  end
  tracer.process_span(process_span)
  kong.tracing.process_span(process_span)

  local sort_by_start_time = function(a,b)
    return a.start_time_ns < b.start_time_ns
  end
  table.sort(spans, sort_by_start_time)

  local data = cjson.encode(spans)

  local ok, err = ngx.timer.at(0, push_data, data, config)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


function _M:ws_close(config)
  local tracer = kong.tracing(tracer_name)
  local span = tracer.active_span()

  if span then
    kong.log.debug("Exit span name: ", span.name)
    span:finish()
  end

  kong.log.debug("Total spans: ", ngx.ctx.KONG_SPANS and #ngx.ctx.KONG_SPANS)

  local spans = {}
  for _, span in ipairs(ngx.ctx.KONG_SPANS or {}) do
    if span.should_sample == false then
      return
    end
    local s = table.clone(span)
    s.tracer = nil
    s.parent = nil
    s.trace_id = to_hex(s.trace_id)
    s.parent_id = s.parent_id and to_hex(s.parent_id)
    s.span_id = to_hex(s.span_id)
    insert(spans, s)
  end

  local sort_by_start_time = function(a,b)
    return a.start_time_ns < b.start_time_ns
  end
  table.sort(spans, sort_by_start_time)

  local data = cjson.encode(spans)

  local ok, err = ngx.timer.at(0, push_data, data, config)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end

return _M
