local resty_http = require "resty.http"
local to_hex = require "resty.string".to_hex
local cjson = require "cjson".new()
cjson.encode_number_precision(16)

local zipkin_reporter_methods = {}
local zipkin_reporter_mt = {
  __name = "kong.plugins.zipkin.reporter";
  __index = zipkin_reporter_methods;
}

local function new_zipkin_reporter(conf)
  local http_endpoint = conf.http_endpoint
  local default_service_name = conf.default_service_name
  assert(type(http_endpoint) == "string", "invalid http endpoint")
  return setmetatable({
                default_service_name = default_service_name;
    http_endpoint = http_endpoint;
    pending_spans = {};
    pending_spans_n = 0;
  }, zipkin_reporter_mt)
end

local span_kind_map = {
  client = "CLIENT";
  server = "SERVER";
  producer = "PRODUCER";
  consumer = "CONSUMER";
}
function zipkin_reporter_methods:report(span)
  local span_context = span:context()

  local zipkin_tags = {}
  for k, v in span:each_tag() do
    -- Zipkin tag values should be strings
    -- see https://zipkin.io/zipkin-api/#/default/post_spans
    -- and https://github.com/Kong/kong-plugin-zipkin/pull/13#issuecomment-402389342
    zipkin_tags[k] = tostring(v)
  end

  local span_kind = zipkin_tags["span.kind"]
  zipkin_tags["span.kind"] = nil

  local localEndpoint do
    local serviceName = zipkin_tags["peer.service"]
    if serviceName then
      zipkin_tags["peer.service"] = nil
      localEndpoint = {
        serviceName = serviceName;
        -- TODO: ip/port from ngx.var.server_name/ngx.var.server_port?
      }
    else
                        -- configurable override of the unknown-service-name spans
                        if self.default_service_name then
                                localEndpoint = {
                                        serviceName = self.default_service_name;
                                }
                        -- needs to be null; not the empty object
                        else
                                localEndpoint = cjson.null
                        end
    end
  end

  local remoteEndpoint do
    local peer_port = span:get_tag "peer.port" -- get as number
    if peer_port then
      zipkin_tags["peer.port"] = nil
      remoteEndpoint = {
        ipv4 = zipkin_tags["peer.ipv4"];
        ipv6 = zipkin_tags["peer.ipv6"];
        port = peer_port; -- port is *not* optional
      }
      zipkin_tags["peer.ipv4"] = nil
      zipkin_tags["peer.ipv6"] = nil
    else
      remoteEndpoint = cjson.null
    end
  end

  local zipkin_span = {
    traceId = to_hex(span_context.trace_id);
    name = span.name;
    parentId = span_context.parent_id and to_hex(span_context.parent_id) or nil;
    id = to_hex(span_context.span_id);
    kind = span_kind_map[span_kind];
    timestamp = span.timestamp * 1000000;
    duration = math.floor(span.duration * 1000000); -- zipkin wants integer
    -- shared = nil; -- We don't use shared spans (server reuses client generated spanId)
    -- TODO: debug?
    localEndpoint = localEndpoint;
    remoteEndpoint = remoteEndpoint;
    tags = zipkin_tags;
    annotations = span.logs -- XXX: not guaranteed by documented opentracing-lua API to be in correct format
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
    method = "POST";
    headers = {
      ["content-type"] = "application/json";
    };
    body = pending_spans;
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
  new = new_zipkin_reporter;
}
