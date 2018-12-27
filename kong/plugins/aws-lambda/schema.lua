local typedefs = require "kong.db.schema.typedefs"

local REGIONS = {
  "ap-northeast-1", "ap-northeast-2",
  "ap-south-1",
  "ap-southeast-1", "ap-southeast-2",
  "ca-central-1",
  "eu-central-1",
  "eu-west-1", "eu-west-2",
  "sa-east-1",
  "us-east-1", "us-east-2",
  "us-gov-west-1",
  "us-west-1", "us-west-2",
}


return {
  name = "aws-lambda",
  fields = {
    { run_on = typedefs.run_on_first },
    { config = {
        type = "record",
        fields = {
          { timeout = {
              type = "number",
              required = true,
              default = 60000
          } },
          { keepalive = {
              type = "number",
              required = true,
              default = 60000
          } },
          { aws_key = {
              type = "string",
              required = true
          } },
          { aws_secret = {
              type = "string",
              required = true
          } },
          { aws_region = {
              type = "string",
              required = true,
              one_of = REGIONS
          } },
          { function_name = {
              type = "string",
              required = true
          } },
          { qualifier = {
              type = "string"
          } },
          { invocation_type = {
              type = "string",
              required = true,
              default = "RequestResponse",
              one_of = { "RequestResponse", "Event", "DryRun" },
          } },
          { log_type = {
              type = "string",
              required = true,
              default = "Tail",
              one_of = { "Tail", "None" },
          } },
          { port = typedefs.port { default = 443 }, },
          { unhandled_status = {
              type = "integer",
              between = { 100, 999 },
          } },
          { forward_request_method = {
              type = "boolean",
              default = false
          } },
          { forward_request_uri = {
              type = "boolean",
              default = false
          } },
          { forward_request_headers = {
              type = "boolean",
              default = false
          } },
          { forward_request_body = {
              type = "boolean",
              default = false
          } },
          { is_proxy_integration = {
              type = "boolean",
              default = false
          } },
        }
    } },
  },
}
