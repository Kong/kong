local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"

local PROTECTED_TAGS = {
  "error",
  "http.method",
  "http.path",
  "http.status_code",
  "kong.balancer.state",
  "kong.balancer.try",
  "kong.consumer",
  "kong.credential",
  "kong.node.id",
  "kong.route",
  "kong.service",
  "lc",
  "peer.hostname",
}

local static_tag = Schema.define {
  type = "record",
  fields = {
    { name = { type = "string", required = true, not_one_of = PROTECTED_TAGS } },
    { value = { type = "string", required = true } },
  },
}

local validate_static_tags = function(tags)
  if type(tags) ~= "table" then
    return true
  end
  local found = {}
  for i = 1, #tags do
    local name = tags[i].name
    if found[name] then
      return nil, "repeated tags are not allowed: " .. name
    end
    found[name] = true
  end
  return true
end

return {
  name = "zipkin",
  fields = {
    { protocols = typedefs.protocols },
    { config = {
        type = "record",
        fields = {
          { local_service_name = { description = "The name of the service as displayed in Zipkin. Customize this name to\ntell your Kong Gateway services apart in Zipkin request traces.", type = "string", required = true, default = "kong" } },
          { http_endpoint = typedefs.url },
          { sample_ratio = { description = "How often to sample requests that do not contain trace IDs.\nSet to `0` to turn sampling off, or to `1` to sample **all** requests. The\nvalue must be between zero (0) and one (1), inclusive.", type = "number",
                             default = 0.001,
                             between = { 0, 1 } } },
          { default_service_name = { description = "Set a default service name to override `unknown-service-name` in the \nZipkin spans.", type = "string", default = nil } },
          { include_credential = { description = "Specify whether the credential of the currently authenticated consumer\nshould be included in metadata sent to the Zipkin server.", type = "boolean", required = true, default = true } },
          { traceid_byte_count = { description = "The length in bytes of each request's Trace ID. The value can be either `8` or `16`.", type = "integer", required = true, default = 16, one_of = { 8, 16 } } },
          { header_type = { description = "All HTTP requests going through the plugin are tagged with a tracing HTTP request.\nThis property codifies what kind of tracing header the plugin expects on incoming requests" type = "string", required = true, default = "preserve",
                            one_of = { "preserve", "ignore", "b3", "b3-single", "w3c", "jaeger", "ot" } } },
          { default_header_type = { description = "Allows specifying the type of header to be added to requests with no pre-existing tracing headers\nand when `config.header_type` is set to `\"preserve\"`.\nWhen `header_type` is set to any other value, `default_header_type` is ignored.\n\nPossible values are `b3`, `b3-single`, `w3c`, `jaeger`, or `ot`.\nSee the entry for `header_type` for value definitions.", type = "string", required = true, default = "b3",
                            one_of = { "b3", "b3-single", "w3c", "jaeger", "ot" } } },
          { tags_header = { description = "The Zipkin plugin will add extra headers to the tags associated with any HTTP\nrequests that come with a header named as configured by this property. The\nformat is `name_of_tag=value_of_tag`, separated by semicolons (`;`).\n\nFor example: with the default value, a request with the header\n`Zipkin-Tags: fg=blue; bg=red` will generate a trace with the tag `fg` with\nvalue `blue`, and another tag called `bg` with value `red`.", type = "string", required = true, default = "Zipkin-Tags" } },
          { static_tags = {  description = "The tags specified on this property will be added to the generated request traces. For example:\n`[ { \"name\": \"color\", \"value\": \"red\" } ]`.", type = "array", elements = static_tag,
                            custom_validator = validate_static_tags } },
          { http_span_name = { description = "Specify whether to include the HTTP path in the span name.\n\nOptions:\n* `method`: Do not include the HTTP path. This is the default.\n* `method_path`: Include the HTTP path.", type = "string", required = true, default = "method", one_of = { "method", "method_path" } } },
          { connect_timeout = typedefs.timeout { default = 2000 } },
          { send_timeout = typedefs.timeout { default = 5000 } },
          { read_timeout = typedefs.timeout { default = 5000 } },
          { http_response_header_for_traceid = { type = "string", default = nil }},
          { phase_duration_flavor = { description = "Specify whether to include the duration of each phase as an annotation or a tag.\n\nOptions:\n* `annotations`: Include the duration of each phase as an annotation. This is the default.\n* `tags`: Include the duration of each phase as a tag.", type = "string", required = true, default = "annotations",
                                      one_of = { "annotations", "tags" } } },
        },
    }, },
  },
}
