local regex_match = ngx.re.match
local find = string.find

local function check_status(status)
  if status and (status < 100 or status > 999) then
    return false, "unhandled_status must be within 100 - 999."
  end

  return true
end

local check_regex = function(value)
  if value then
    for _, rule in ipairs(value) do
      local _, err = regex_match("just a string to test", rule)
      if err then
        return false, "value '" .. rule .. "' is not a valid regex"
      end
    end
  end
  return true
end

local function check_for_value(value)
  if value then
    for i, entry in ipairs(value) do
      local ok = find(entry, ":")
      if not ok then
        return false, "key '" .. entry .. "' has no value"
      end
    end
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
      required = true,
    },
    aws_secret = {
      type = "string",
      required = true,
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
    dynamic_lambda_key = {
      type = "string"
    },
    dynamic_lambda_whitelist = {
      type = "array",
      func = check_regex
    },
    dynamic_lambda_aliases = {
       type = "array",
       func = check_for_value
    }
  },
}
