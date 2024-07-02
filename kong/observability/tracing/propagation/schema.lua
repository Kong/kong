local Schema = require "kong.db.schema"
local formats = require "kong.observability.tracing.propagation.utils".FORMATS
local validate_header_name = require("kong.tools.http").validate_header_name


local extractors = {}
for _, ext in pairs(formats) do
  -- b3 and b3-single formats use the same extractor: b3
  if ext ~= "b3-single" then
    table.insert(extractors, ext)
  end
end
local injectors = {}
for _, inj in pairs(formats) do
 table.insert(injectors, inj)
end


return Schema.define {
  type = "record",
  fields = {
    {
      extract = {
        description = "Header formats used to extract tracing context from incoming requests. If multiple values are specified, the first one found will be used for extraction. If left empty, Kong will not extract any tracing context information from incoming requests and generate a trace with no parent and a new trace ID.",
        type = "array",
        elements = {
          type = "string",
          one_of = extractors
        },
      }
    },
    {
      clear = {
        description = "Header names to clear after context extraction. This allows to extract the context from a certain header and then remove it from the request, useful when extraction and injection are performed on different header formats and the original header should not be sent to the upstream. If left empty, no headers are cleared.",
        type = "array",
        elements = {
          type = "string",
          custom_validator = validate_header_name,
        }
      }
    },
    {
      inject = {
        description = "Header formats used to inject tracing context. The value `preserve` will use the same header format as the incoming request. If multiple values are specified, all of them will be used during injection. If left empty, Kong will not inject any tracing context information in outgoing requests.",
        type = "array",
        elements = {
          type = "string",
          one_of = { "preserve", table.unpack(injectors) } -- luacheck: ignore table
        },
      }
    },
    {
      default_format = {
        description = "The default header format to use when extractors did not match any format in the incoming headers and `inject` is configured with the value: `preserve`. This can happen when no tracing header was found in the request, or the incoming tracing header formats were not included in `extract`.",
        type = "string",
        one_of = injectors,
        required = true,
      },
    }
  }
}
