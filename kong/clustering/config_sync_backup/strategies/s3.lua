-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local AWS = require("resty.aws")
local normalize = require("kong.tools.uri").normalize
local socket_url = require("socket.url")
local xmlua = require("xmlua")
local tablex = require("pl.tablex")
local kong = kong


local xml_parse = xmlua.XML.parse


-- this must happen at init phase because we need to get the AWS environment variables
-- for now the kong.clustering.new() is called by kong.init at init phase
assert(ngx.get_phase() == "init", "please make sure S3 strategy is required at init phase")
local AWS_config = require("resty.aws.config")
local aws_endpoint_env = os.getenv("AWS_CONFIG_STORAGE_ENDPOINT")


local s3_instance
local empty = {}


local _M = {}
local _MT = { __index = _M, }


local function endpoint_settings(config)
  local endpoint = config.endpoint or aws_endpoint_env

  if not endpoint then
    return empty
  end
  
  local parsed_url, err = socket_url.parse(endpoint)

  if err then
    error("invalid endpoint: " .. err)
  end

  local port = tonumber(parsed_url.port)
  local scheme = parsed_url.scheme
  local tls = (scheme == "https")

  return {
    scheme = scheme,
    tls = tls,
    endpoint = parsed_url.host,
    port = port or (tls and 443 or 80),
  }
end


function _M.init_worker()
  -- TODO: avoid http request to get the region
  local global_config = AWS_config.global
  if not (global_config.region or global_config.signingRegion) then
    error("S3 region is not configured")
  end

  -- to support third party s3 compatible storage that does not support bucket in host
  global_config.s3_bucket_in_path = true
  local aws_instance = assert(AWS(global_config))
  s3_instance = assert(aws_instance:S3(endpoint_settings(global_config)))
end


function _M.new(gateway_version, url)
  local self = {
    url = url,
    gateway_version = gateway_version,
  }

  -- todo: should we support credential in url?
  local parsed_url, err = socket_url.parse(url)

  if err then
    error("invalid s3 url: " .. err)
  end

  self.bucket = parsed_url.host
  local path = parsed_url.path

  if path:sub(1,1) == "/" then
    path = path:sub(2)
  end

  self.key = normalize(path .. "/" .. gateway_version .. "/config.json", true)

  return setmetatable(self, _MT)
end


local function aws_call(instance, func, args)
  local res, err = instance[func](instance, args)
  if not res then
    return nil, "failed to send request: " .. err
  end

  if res.status ~= 200 then
    local error_node = xml_parse(res.body):search("/Error/Message")
    err = error_node[1] and error_node[1]:text() or res.body
    return nil, err
  end

  return res
end


function _M:backup_config(config)
  local call_config
  if kong.configuration.cluster_fallback_export_s3_config then
    call_config = tablex.deepcopy(kong.configuration.cluster_fallback_export_s3_config)
  else
    call_config = {}
  end

  call_config.Bucket = self.bucket
  call_config.Key = self.key
  call_config.Body = config
  call_config.ContentType = "application/json"

  local res, err = aws_call(s3_instance, "putObject", call_config)

  if not res then
    return nil, err .. " uploading to bucket: " .. self.bucket .. " key: " .. self.key
  end

  return true
end


function _M:fetch_config()
  local res, err = aws_call(s3_instance, "getObject", {
    Bucket = self.bucket,
    Key = self.key,
  })

  if not res then
    return nil, err .. " fetching object: " .. self.bucket .. " key: " .. self.key
  end

  return res.body or ""
end


return _M
