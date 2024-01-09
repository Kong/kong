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
local election = require("kong.clustering.config_sync_backup.election")
local date = require "date"
local kong = kong
local ngx_now = ngx.now
local epoch = date.epoch()


local xml_parse = xmlua.XML.parse

local ngx = ngx
local log = ngx.log
local WARN = ngx.WARN

local ns_aws06 = {
  {
    prefix = "aws06",
    href = "http://s3.amazonaws.com/doc/2006-03-01/",
  }
}

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


local fill_fallback do
  local fallback_argugments

  function fill_fallback(args)
    if not fallback_argugments then
      fallback_argugments = kong.configuration.cluster_fallback_export_s3_config or {}
    end
  
    for k, v in pairs(fallback_argugments) do
      if args[k] == nil then
        args[k] = v
      end
    end

    return args
  end
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
    node_id = kong.node.get_id(),
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
  self.election_prefix = normalize(path .. "/" .. gateway_version .. "/election", true) .. "/"

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
  local res, err = aws_call(s3_instance, "putObject", fill_fallback {
    Bucket = self.bucket,
    Key = self.key,
    Body = config,
    ContentType = "application/json",
    Metadata = {
      uploader = self.node_id,
    }
  })

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


function _M:start_election_timer(election_interval, set_enable_export)
  self.election = election.new({
    set_enable_export = set_enable_export,
    election_interval = election_interval,
    storage = self,
  })

  self.election:start_timer()
end


function _M:register_node()
  local key = self.election:to_file_name(self.election_prefix)
  local res, err = aws_call(s3_instance, "putObject", fill_fallback {
    Bucket = self.bucket,
    Key = key,
    Body = "",
    ContentType = "text/plain",
  })

  if not res then
    return nil, err .. " registering node to bucket: " .. self.bucket .. " key: " .. key
  end

  return true
end


local function extract_object(storage, xml_object)
  local candidate_name = xml_object:search("aws06:Key", ns_aws06)[1]:text()
  local candidate = storage.election.parse_node_information(storage.election_prefix, candidate_name)
  local refreshed_time_text = xml_object:search("aws06:LastModified", ns_aws06)[1]:text()
  candidate.refreshed_time = (date(refreshed_time_text) - epoch):spanseconds()

  return candidate
end


function _M:get_candidates()
  local res, err = aws_call(s3_instance, "listObjectsV2", {
    Bucket = self.bucket,
    Prefix = self.election_prefix,
    MaxKeys = 1000, -- unlikely to have more than 1000 nodes
  })

  if not res then
    return nil, err .. " listing objects from bucket: " .. self.bucket .. " prefix: " .. self.election_prefix
  end

  if not res.body then
    return {}
  end

  local ok, objects, truncated = pcall(function()
    local list_bucket_result = assert(xml_parse(res.body):search("//aws06:ListBucketResult", ns_aws06)[1], "ListBucketResult not found")
    return list_bucket_result:search("aws06:Contents", ns_aws06), list_bucket_result:search("aws06:IsTruncated", ns_aws06)[1]:text()
  end)

  if not ok then
    return nil, objects .. " parsing result when listing objects from bucket: " .. self.bucket .. " prefix: " .. self.election_prefix
  end

  -- emit a warning in this case
  if truncated == "true" then
    log(WARN, "too many objects in bucket: ", self.bucket, " prefix: ", self.election_prefix, " consider set a lifecycle rule to remove outdated objects")
  end

  local now = ngx_now()
  local i = 1

  return function()
    -- return first fresh object if exists
    while true do
      -- next object
      local object = objects[i]
      i = i + 1

      if not object then
        return nil
      end

      local ok, registration = pcall(extract_object, self, object)

      if not ok then
        -- ignore incorrectly formatted object and continue
        log(WARN, "failed to extract a registration object: ", objects[i]:to_xml())
      elseif self.election:is_fresh(registration.refreshed_time, now) then
        return registration
      end
    end
  end
end


return _M
