local resty_http = require "resty.http"
local to_hex = require "resty.string".to_hex
local cjson = require "cjson".new()
cjson.encode_number_precision(16)

local floor = math.floor
local gsub = string.gsub

local zipkin_reporter_methods = {}
local zipkin_reporter_mt = {
  __index = zipkin_reporter_methods,
}


local function new_zipkin_reporter(conf)
  local http_endpoint = conf.http_endpoint
  local default_service_name = conf.default_service_name
  assert(type(http_endpoint) == "string", "invalid http endpoint")
  return setmetatable({
    default_service_name = default_service_name,
    http_endpoint = http_endpoint,
    pending_spans = {},
    pending_spans_n = 0,
  }, zipkin_reporter_mt)
end


local span_kind_map = {
  client = "CLIENT",
  server = "SERVER",
  producer = "PRODUCER",
  consumer = "CONSUMER",
}


function zipkin_reporter_methods:report(span)
  local span_context = span:context()

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

  local span_kind = zipkin_tags["span.kind"]
  zipkin_tags["span.kind"] = nil

  -- rename component tag to lc ("local component")
  local component = zipkin_tags["component"]
  zipkin_tags["component"] = nil
  zipkin_tags["lc"] = component

  local localEndpoint = {
    serviceName = "kong"
  }

  local remoteEndpoint do
    local serviceName = zipkin_tags["peer.service"] or
                        self.default_service_name -- can be nil

    local peer_port = span:get_tag "peer.port" -- get as number
    if peer_port or serviceName then
      remoteEndpoint = {
        serviceName = serviceName,
        ipv4 = zipkin_tags["peer.ipv4"],
        ipv6 = zipkin_tags["peer.ipv6"],
        port = peer_port,
      }
      zipkin_tags["peer.service"] = nil
      zipkin_tags["peer.port"] = nil
      zipkin_tags["peer.ipv4"] = nil
      zipkin_tags["peer.ipv6"] = nil
    else
      remoteEndpoint = cjson.null
    end
  end

  local annotations do
    local n_logs = span.n_logs
    if n_logs > 0 then
      annotations = kong.table.new(n_logs, 0)
      for i = 1, n_logs do
        local log = span.logs[i]

        -- Shortens the log strings into annotation values
        -- for Zipkin. "kong.access.start" becomes "kas"
        local value = gsub(log.key .. "." .. log.value,
                           "%.?(%w)[^%.]*",
                           "%1")
        annotations[i] = {
          value     = value,
          timestamp = floor(log.timestamp),
        }
      end
    end
  end

  if not next(zipkin_tags) then
    zipkin_tags = nil
  end

  local zipkin_span = {
    traceId = to_hex(span_context.trace_id),
    name = span.name,
    parentId = span_context.parent_id and to_hex(span_context.parent_id) or nil,
    id = to_hex(span_context.span_id),
    kind = span_kind_map[span_kind],
    timestamp = floor(span.timestamp * 1000000),
    duration = floor(span.duration * 1000000), -- zipkin wants integer
    -- shared = nil, -- We don't use shared spans (server reuses client generated spanId)
    -- TODO: debug?
    localEndpoint = localEndpoint,
    remoteEndpoint = remoteEndpoint,
    tags = zipkin_tags,
    annotations = annotations,
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

  local httpc = resty_http.new()
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
  new = new_zipkin_reporter,
}
