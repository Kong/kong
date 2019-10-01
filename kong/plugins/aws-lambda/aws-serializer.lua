-- serializer to wrap the current request into the Amazon API gateway
-- format as described here:
-- https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format


local EMPTY = {}

local ngx_req_get_headers  = ngx.req.get_headers
local ngx_req_get_uri_args = ngx.req.get_uri_args
local ngx_encode_base64    = ngx.encode_base64
local ngx_req_read_body    = ngx.req.read_body
local ngx_req_get_body_data= ngx.req.get_body_data
local ngx_req_get_body_file= ngx.req.get_body_file
local ngx_log              = ngx.log
local ERR                  = ngx.ERR


return function(ctx, config)
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
  local body, isBase64Encoded
  do
    ngx_req_read_body()
    body = ngx_req_get_body_data()
    if not body then
      local body_filepath = ngx_req_get_body_file()
      if body_filepath then
        if config.skip_large_bodies then
          ngx_log(ERR, "request body was buffered to disk, too large")
        else
          local file = io.open(body_filepath, "rb")
          body = file:read("*all")
          file:close()
        end
      end
    end

    if body ~= "" then
      body = ngx_encode_base64(body)
      isBase64Encoded = true
    else
      isBase64Encoded = false
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

  return request
end
