local Errors = require "kong.dao.errors"

local function check_status(status)
  if status and (status < 100 or status > 999) then
    return false, "unhandled_status must be within 100 - 999."
  end

  return true
end

return {
  fields = {
    timeout = {
      type = "number",
      default = 60000,
      required = true,
    },
    keepalive = {
      type = "number",
      default = 60000,
      required = true,
    },
    aws_key = {
      type = "string",
    },
    aws_secret = {
      type = "string",
    },
    aws_region = {
      type = "string",
      required = true,
      enum = {
        "us-east-1",
        "us-east-2",
        "us-west-1",
        "us-west-2",
        "ap-northeast-1",
        "ap-northeast-2",
        "ap-southeast-1",
        "ap-southeast-2",
        "ap-south-1",
        "ca-central-1",
        "eu-central-1",
        "eu-west-1",
        "eu-west-2",
        "sa-east-1",
      },
    },
    function_name = {
      type= "string",
      required = true,
    },
    qualifier = {
      type = "string",
    },
    invocation_type = {
      type = "string",
      required = true,
      default = "RequestResponse",
      enum = {
        "RequestResponse",
        "Event",
        "DryRun",
      }
    },
    log_type = {
      type = "string",
      required = true,
      default = "Tail",
      enum = {
        "Tail",
        "None",
      }
    },
    port = {
      type = "number",
      default = 443,
    },
    unhandled_status = {
      type = "number",
      func = check_status,
    },
    forward_request_method = {
      type = "boolean",
      default = false,
    },
    forward_request_uri = {
      type = "boolean",
      default = false,
    },
    forward_request_headers = {
      type = "boolean",
      default = false,
    },
    forward_request_body = {
      type = "boolean",
      default = false,
    },
    is_proxy_integration = {
      type = "boolean",
      default = false,
    },
    awsgateway_compatible = {
      type = "boolean",
      default = false,
    },
    proxy_scheme = {
      type = "string",
      enum = {
        "http",
        "https",
      }
    },
    proxy_url = {
      type = "string"
    },
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if (plugin_t.aws_key or "") == "" then
      -- not provided
      if (plugin_t.aws_secret or "") ~= "" then
        return false, Errors.schema "You need to set both or neither of aws_key and aws_secret"
      end
    else
      -- provided
      if (plugin_t.aws_secret or "") == "" then
        return false, Errors.schema "You need to set both or neither of aws_key and aws_secret"
      end
    end
    if plugin_t.proxy_url and not plugin_t.proxy_scheme then
      return false, Errors.schema "You need to set proxy_scheme when proxy_url is set"
    end
    return true
  end
}
