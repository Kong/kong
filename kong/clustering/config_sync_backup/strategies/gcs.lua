-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local GCP = require("resty.gcp")
local access_token = require "resty.gcp.request.credentials.accesstoken"
local normalize = require("kong.tools.uri").normalize
local ffi = require("ffi")
local cjson_encode = require("cjson.safe").encode
local socket_url = require("socket.url")
local C = ffi.C
local _M = {}
local _MT = { __index = _M, }

-- this must happen at init phase because we need to get the GCP environment variables
-- for now the kong.clustering.new() is called by kong.init at init phase
assert(ngx.get_phase() == "init", "please make sure GCP strategy is required at init phase")
local GCP_ACCESS_TOKEN_ENV = os.getenv("GCP_SERVICE_ACCOUNT")
local GCP_ACCESS_TOKEN


ffi.cdef [[
  int setenv(const char *name, const char *value, int overwrite);
]]

-- TODO: gcp also needs a credential manager
local function get_token()
  -- First time. Initialize the token
  if not GCP_ACCESS_TOKEN then
    assert(GCP_ACCESS_TOKEN_ENV, "GCP access token is not available")
    -- to be compatible with older version of resty.gcp
    C.setenv("GCP_SERVICE_ACCOUNT", GCP_ACCESS_TOKEN_ENV, 1)
    -- this call will throw an error if the token is invalid
    GCP_ACCESS_TOKEN = access_token:new(GCP_ACCESS_TOKEN_ENV)
  end

  if GCP_ACCESS_TOKEN:needsRefresh() then
    assert(GCP_ACCESS_TOKEN:refresh(GCP_ACCESS_TOKEN),
           "GCP_SERVICE_ACCOUNT invalid (invalid service account)")
  end

  return GCP_ACCESS_TOKEN
end

local storage_v1

function _M.init_worker()
  local gcp_instance = GCP()
  storage_v1 = gcp_instance.storage_v1.objects
end

function _M.new(gateway_version, url)
  local self = {
    url = url,
    gateway_version = gateway_version,
  }

  local parsed_url, err = socket_url.parse(url)

  if err then
    error("invalid gcp url: " .. err)
  end

  
  self.bucket = parsed_url.host
  local path = parsed_url.path

  if path:sub(1,1) == "/" then
    path = path:sub(2)
  end

  self.key = normalize(path .. "/" .. gateway_version .. "/config.json", true)

  return setmetatable(self, _MT)
end

local function gcp_call(method, args, body)
  local ok, err = pcall(get_token)
  if ok then
    return storage_v1[method](get_token(), args, body)
  else
    if type(err) == "table" then
      if err.reason then
        err = err.reason
      else
        err = cjson_encode(err)
      end
    end
    return nil, err
  end
end

function _M:backup_config(config)
  local res, err = gcp_call("insert", {
    bucket = self.bucket,
    name = self.key,
  }, config)

  if not res then
    return nil, err
  end

  return true
end

function _M:fetch_config()
  local res, err = gcp_call("get", {
    bucket = self.bucket,
    object = self.key,
    alt = "media",
  })

  if not res then
    return nil, err
  end

  return res or ""
end

return _M
