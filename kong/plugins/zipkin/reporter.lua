local resty_http = require "resty.http"
local to_hex = require "resty.string".to_hex
local cjson = require "cjson".new()
cjson.encode_number_precision(16)

local zipkin_reporter_methods = {}
local zipkin_reporter_mt = {
  __index = zipkin_reporter_methods,
}


-- Utility function to set either ipv4 or ipv6 tags
-- nginx apis don't have a flag to indicate whether an address is v4 or v6
local function ip_kind(addr)
  -- use the presence of ":" to signal v6 (v4 has no colons)
  if addr:find(":", 1, true) then
    return "ipv6"
  else
    return "ipv4"
  end
end


local function new(http_endpoint, default_service_name, local_service_name, connect_timeout, send_timeout, read_timeout)
  return setmetatable({
    default_service_name = default_service_name,
    local_service_name = local_service_name,
    http_endpoint = http_endpoint,
    connect_timeout = connect_timeout,
    send_timeout = send_timeout,
    read_timeout = read_timeout,
    pending_spans = {},
    pending_spans_n = 0,
  }, zipkin_reporter_mt)
end


function zipkin_reporter_methods:report(span)
  if not span.should_sample then
    return
  end

  local zipkin_tags = {}
  for k, v in span:each_tag() do
    -- Zipkin tag values should be strings
    -- see https://zipkin.io/zipkin-api/#/default/post_spans
    -- and https://github.com/Kong/kong-plugin-zipkin/pull/13#issuecomment-402389342
    -- Zipkin tags should be non-empty
    -- see https://github.com/openzipkin/zipkin/pull/2834#discussion_r332125458
    if v ~= "" then
      zipkin_tags[k] = tostring(v)
    end
  end

  local remoteEndpoint do
    local serviceName = span.service_name or self.default_service_name -- can be nil
    if span.port or serviceName then
      remoteEndpoint = {
        serviceName = serviceName,
        port = span.port,
      }
      if span.ip then
        remoteEndpoint[ip_kind(span.ip)] = span.ip
      end
    else
      remoteEndpoint = cjson.null
    end
  end


  if not next(zipkin_tags) then
    zipkin_tags = nil
  end

  local zipkin_span = {
    traceId = to_hex(span.trace_id),
    name = span.name,
    parentId = span.parent_id and to_hex(span.parent_id) or nil,
    id = to_hex(span.span_id),
    kind = span.kind,
    timestamp = span.timestamp,
    duration = span.duration,
    -- shared = nil, -- We don't use shared spans (server reuses client generated spanId)
    localEndpoint = { serviceName = self.local_service_name },
    remoteEndpoint = remoteEndpoint,
    tags = zipkin_tags,
    annotations = span.annotations,
  }

  local i = self.pending_spans_n + 1
  self.pending_spans[i] = zipkin_span
  self.pending_spans_n = i
end


function zipkin_reporter_methods:flush()
  if self.pending_spans_n == 0 then
    return true
  end

  local pending_spans = cjson.encode(self.pending_spans)
  self.pending_spans = {}
  self.pending_spans_n = 0

  if self.http_endpoint == nil or self.http_endpoint == ngx.null then
    return true
  end

  local httpc = resty_http.new()
  httpc:set_timeouts(self.connect_timeout, self.send_timeout, self.read_timeout)
  local res, err = httpc:request_uri(self.http_endpoint, {
    method = "POST",
    headers = {
      ["content-type"] = "application/json",
    },
    body = pending_spans,
  })
  -- TODO: on failure, retry?
  if not res then
    return nil, "failed to request: " .. err
  elseif res.status < 200 or res.status >= 300 then
    return nil, "failed: " .. res.status .. " " .. res.reason
  end
  return true
end


return {
  new = new,
}
