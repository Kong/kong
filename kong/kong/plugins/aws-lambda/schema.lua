local typedefs = require "kong.db.schema.typedefs"

return {
  name = "aws-lambda",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        { timeout = {
          type = "number",
          required = true,
          default = 60000,
          description = "An optional timeout in milliseconds when invoking the function.",
        } },
        { keepalive = {
          type = "number",
          required = true,
          default = 60000,
          description = "An optional value in milliseconds that defines how long an idle connection lives before being closed.",
        } },
        { aws_key = {
          type = "string",
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          referenceable = true,
          description = "The AWS key credential to be used when invoking the function.",
        } },
        { aws_secret = {
          type = "string",
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          referenceable = true,
          description = "The AWS secret credential to be used when invoking the function. ",
        } },
        { aws_assume_role_arn = { description = "The target AWS IAM role ARN used to invoke the Lambda function.", type = "string",
          encrypted = true, -- Kong Enterprise-exclusive feature, does nothing in Kong CE
          referenceable = true,
        } },
        { aws_role_session_name = { description = "The identifier of the assumed role session.", type = "string",
          default = "kong"
        } },
        { aws_sts_endpoint_url = typedefs.url },
        { aws_region = typedefs.host },
        { function_name = {
          type = "string",
          required = false,
          description = "The AWS Lambda function to invoke. Both function name and function ARN (including partial) are supported."
        } },
        { qualifier = {
          type = "string",
          description = "The qualifier to use when invoking the function."
        } },
        { invocation_type = {
          description = "The InvocationType to use when invoking the function. Available types are RequestResponse, Event, DryRun.",
          type = "string",
          required = true,
          default = "RequestResponse",
          one_of = { "RequestResponse", "Event", "DryRun" }
        } },
        { log_type = {
          description = "The LogType to use when invoking the function. By default, None and Tail are supported.",
          type = "string",
          required = true,
          default = "Tail",
          one_of = { "Tail", "None" }
        } },
        { host = typedefs.host },
        { port = typedefs.port { default = 443 }, },
        { disable_https = { type = "boolean", default = false }, },
        { unhandled_status = {
          description = "The response status code to use (instead of the default 200, 202, or 204) in the case of an Unhandled Function Error.",
          type = "integer",
          between = { 100, 999 },
        } },
        { forward_request_method = {
          description = "An optional value that defines whether the original HTTP request method verb is sent in the request_method field of the JSON-encoded request.",
          type = "boolean",
          default = false,
        } },
        { forward_request_uri = {
          description = "An optional value that defines whether the original HTTP request URI is sent in the request_uri field of the JSON-encoded request.",
          type = "boolean",
          default = false,
        } },
        { forward_request_headers = {
          description = "An optional value that defines whether the original HTTP request headers are sent as a map in the request_headers field of the JSON-encoded request.",
          type = "boolean",
          default = false,
        } },
        { forward_request_body = {
          description = "An optional value that defines whether the request body is sent in the request_body field of the JSON-encoded request. If the body arguments can be parsed, they are sent in the separate request_body_args field of the request. ",
          type = "boolean",
          default = false,
        } },
        { is_proxy_integration = {
          description = "An optional value that defines whether the response format to receive from the Lambda to this format.",
          type = "boolean",
          default = false,
        } },
        { awsgateway_compatible = {
          description = "An optional value that defines whether the plugin should wrap requests into the Amazon API gateway.",
          type = "boolean",
          default = false,
        } },
        { proxy_url = typedefs.url },
        { skip_large_bodies = {
          description = "An optional value that defines whether Kong should send large bodies that are buffered to disk",
          type = "boolean",
          default = true,
        } },
        { base64_encode_body = {
          description = "An optional value that Base64-encodes the request body.", type = "boolean",
          default = true,
        } },
        { aws_imds_protocol_version = {
          description = "Identifier to select the IMDS protocol version to use: `v1` or `v2`.", type = "string",
          required = true,
          default = "v1",
          one_of = { "v1", "v2" }
        } },
        { empty_arrays_mode = { -- TODO: this config field is added for backward compatibility and will be removed in next major version
          description = "An optional value that defines whether Kong should send empty arrays (returned by Lambda function) as `[]` arrays or `{}` objects in JSON responses. The value `legacy` means Kong will send empty arrays as `{}` objects in response",
          type = "string",
          required = true,
          default = "legacy",
          one_of = { "legacy", "correct" }
        } },
      }
    },
  } },
  entity_checks = {
    { mutually_required = { "config.aws_key", "config.aws_secret" } },
    { custom_entity_check = {
        field_sources = { "config.proxy_url" },
        fn = function(entity)
          local proxy_url = entity.config and entity.config.proxy_url

          if type(proxy_url) == "string" then
            local scheme = proxy_url:match("^([^:]+)://")

            if scheme and scheme ~= "http" then
              return nil, "proxy_url scheme must be http"
            end
          end

          return true
        end,
      }
    },
  }
}
