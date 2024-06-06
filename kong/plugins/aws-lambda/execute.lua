local http = require "resty.luasocket.http"
local build_request = require("resty.aws.request.build")
local sign_request = require("resty.aws.request.sign")

-- This file is a workaround to support response streaming for AWS Lambda.
-- The content of this file is modified from:
-- * https://github.com/Kong/lua-resty-aws/blob/9e66799319fcb6ab37cf7fbc408f2d8b6adc7851/src/resty/aws/request/execute.lua#L18
-- * https://github.com/Kong/lua-resty-aws/blob/9e66799319fcb6ab37cf7fbc408f2d8b6adc7851/src/resty/aws/init.lua#L307
-- Thus this file should be removed when the resty-aws library is ready to support response streaming.
-- See https://github.com/Kong/lua-resty-aws/issues/117 for more details.
-- TODO: remove this file.

-- implement AWS api protocols.
-- returns the raw response to support streaming.
--
-- Input parameters:
-- * signed_request table
local function execute_request_raw(signed_request)
  local httpc = http.new()
  httpc:set_timeout(signed_request.timeout or 60000)

  local ok, err = httpc:connect {
    host = signed_request.host,
    port = signed_request.port,
    scheme = signed_request.tls and "https" or "http",
    ssl_server_name = signed_request.host,
    ssl_verify = signed_request.ssl_verify,
    proxy_opts = signed_request.proxy_opts,
  }
  if not ok then
    return nil, ("failed to connect to '%s://%s:%s': %s"):format(
      signed_request.tls and "https" or "http",
      tostring(signed_request.host),
      tostring(signed_request.port),
      tostring(err))
  end

  local response, err = httpc:request({
    path = signed_request.path,
    method = signed_request.method,
    headers = signed_request.headers,
    query = signed_request.query,
    body = signed_request.body,
  })
  if not response then
    return nil, ("failed sending request to '%s:%s': %s"):format(
      tostring(signed_request.host),
      tostring(signed_request.port),
      tostring(err))
  end

  if signed_request.keepalive_idle_timeout then
    httpc:set_keepalive(signed_request.keepalive_idle_timeout)
  else
    httpc:close()
  end

  return response, err
end

local function invokeWithResponseStream(self, params)
  params = params or {}

  -- print(require("pl.pretty").write(params))
  -- print(require("pl.pretty").write(self.config))

  -- generate request data and format it according to the protocol
  local request = build_request({
    name = "InvokeWithResponseStream",
    http = {
      method = "POST",
      requestUri = "/2021-11-15/functions/" .. params.FunctionName .. "/response-streaming-invocations"
    },
    input = {
      shape = "InvokeWithResponseStreamRequest"
    },
    output = {
      shape = "InvokeWithResponseStreamResponse"
    },
    errors = { {
      shape = "ServiceException"
    }, {
      shape = "ResourceNotFoundException"
    }, {
      shape = "InvalidRequestContentException"
    }, {
      shape = "RequestTooLargeException"
    }, {
      shape = "UnsupportedMediaTypeException"
    }, {
      shape = "TooManyRequestsException"
    }, {
      shape = "InvalidParameterValueException"
    }, {
      shape = "EC2UnexpectedException"
    }, {
      shape = "SubnetIPAddressLimitReachedException"
    }, {
      shape = "ENILimitReachedException"
    }, {
      shape = "EFSMountConnectivityException"
    }, {
      shape = "EFSMountFailureException"
    }, {
      shape = "EFSMountTimeoutException"
    }, {
      shape = "EFSIOException"
    }, {
      shape = "SnapStartException"
    }, {
      shape = "SnapStartTimeoutException"
    }, {
      shape = "SnapStartNotReadyException"
    }, {
      shape = "EC2ThrottledException"
    }, {
      shape = "EC2AccessDeniedException"
    }, {
      shape = "InvalidSubnetIDException"
    }, {
      shape = "InvalidSecurityGroupIDException"
    }, {
      shape = "InvalidZipFileException"
    }, {
      shape = "KMSDisabledException"
    }, {
      shape = "KMSInvalidStateException"
    }, {
      shape = "KMSAccessDeniedException"
    }, {
      shape = "KMSNotFoundException"
    }, {
      shape = "InvalidRuntimeException"
    }, {
      shape = "ResourceConflictException"
    }, {
      shape = "ResourceNotReadyException"
    }, {
      shape = "RecursiveInvocationException"
    } },
  }, self.config, params)

  -- print request
  -- print(require("pl.pretty").write(request))

  -- sign the request according to the signature version required
  local signed_request, err = sign_request(self.config, request)
  if not signed_request then
    return nil, "failed to sign request: " .. tostring(err)
  end

  -- print(require("pl.pretty").write(signed_request))

  if self.config.dry_run then
    return signed_request
  end
  -- execute the request
  local response, err = execute_request_raw(signed_request)
  if not response then
    return nil, "Lambda:invokeWithResponseStream()" .. " " .. tostring(err)
  end

  return response
end

return invokeWithResponseStream
