-- serializer to wrap the current request into the Amazon API gateway
-- format as described here:
-- https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format


local public_utils = require "kong.tools.public"


local EMPTY = {}

local ngx_req_get_headers = ngx.req.get_headers
local ngx_req_get_uri_args = ngx.req.get_uri_args
local ngx_encode_base64    = ngx.encode_base64


return function(ctx)
  ctx = ctx or ngx.ctx
  local var = ngx.var

  -- prepare headers
  local headers = ngx_req_get_headers()
  local multiValueHeaders = {}
  for hname, hvalue in pairs(headers) do
    if type(hvalue) == "table" then
      -- multi value
      multiValueHeaders[hname] = hvalue
      headers[hname] = hvalue[1]

    else
      -- single value
      multiValueHeaders[hname] = { hvalue }
    end
  end

  -- prepare url-captures/path-parameters
  local pathParameters = {}
  for name, value in pairs(ctx.router_matches.uri_captures or EMPTY) do
    if type(name) == "string" then  -- skip numerical indices, only named
      pathParameters[name] = value
    end
  end

  -- query parameters
  local queryStringParameters = ngx_req_get_uri_args()
  local multiValueQueryStringParameters = {}
  for qname, qvalue in pairs(queryStringParameters) do
    if type(qvalue) == "table" then
      -- multi value
      multiValueQueryStringParameters[qname] = qvalue
      queryStringParameters[qname] = qvalue[1]

    else
      -- single value
      multiValueQueryStringParameters[qname] = { qvalue }
    end
  end

  -- prepare body
  local isBase64Encoded = false
  local body
  do
    local _, err_code, body = public_utils.get_body_info()
    if err_code == public_utils.req_body_errors.unknown_ct then
      -- don't know what this body MIME type is, base64 it just in case
      body = ngx_encode_base64(body)
      isBase64Encoded = true
    end
  end

  -- prepare path
  local path = var.request_uri:match("^([^%?]+)")  -- strip any query args

  local request = {
    resource                        = ctx.router_matches.uri,
    path                            = path,
    httpMethod                      = var.request_method,
    headers                         = headers,
    multiValueHeaders               = multiValueHeaders,
    pathParameters                  = pathParameters,
    queryStringParameters           = queryStringParameters,
    multiValueQueryStringParameters = multiValueQueryStringParameters,
    body                            = body,
    isBase64Encoded                 = isBase64Encoded,
  }

  --print(require("pl.pretty").write(request))
  --print(require("pl.pretty").write(ctx.router_matches))

  return request
end