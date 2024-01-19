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
local election = require("kong.clustering.config_sync_backup.election")
local date = require "date"
local epoch = date.epoch()
local ngx_now = ngx.now
local ipairs = ipairs
local C = ffi.C
local _M = {}
local _MT = { __index = _M, }

local ngx = ngx
local log = ngx.log
local WARN = ngx.WARN

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
    if GCP_ACCESS_TOKEN_ENV then
      -- to be compatible with older version of resty.gcp
      C.setenv("GCP_SERVICE_ACCOUNT", GCP_ACCESS_TOKEN_ENV, 1)
      -- this call will throw an error if the token is invalid
      GCP_ACCESS_TOKEN = access_token:new(GCP_ACCESS_TOKEN_ENV)
    else
      GCP_ACCESS_TOKEN = access_token:new()
    end
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
  storage_v1 = gcp_instance.storage_v1
end


function _M.new(gateway_version, url)
  local self = {
    url = url,
    gateway_version = gateway_version,
    node_id = kong.node.get_id(),
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
  self.election_prefix = normalize(path .. "/" .. gateway_version .. "/election", true) .. "/"

  return setmetatable(self, _MT)
end


local function gcp_call(api, args, body)
  local ok, err = pcall(get_token)
  if ok then
    return api(get_token(), args, body)
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
  local res, err = gcp_call(storage_v1.objects.insert, {
    bucket = self.bucket,
    name = self.key,
  }, config)

  if not res then
    return nil, err
  end

  return true
end

function _M:fetch_config()
  local res, err = gcp_call(storage_v1.objects.get, {
    bucket = self.bucket,
    object = self.key,
    alt = "media",
  })

  if not res then
    return nil, err
  end

  return res or ""
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
  -- GCP support "timeCreated" and "updated" fields so we do not have to encode the time in the key
  local key = self.election_prefix .. self.node_id
  -- update to refresh the timestamp if the node already registered
  local res = gcp_call(storage_v1.objects.update, {
    bucket = self.bucket,
    object = key,
  }, "")

  if res then
    return true
  end

  local err
  -- if the node is not registered, create a new object
  res, err = gcp_call(storage_v1.objects.insert, {
    bucket = self.bucket,
    name = key,
  }, "")

  if not res then
    return nil, err .. " registering node to bucket: " .. self.bucket .. " key: " .. key
  end

  return true
end


local function get_timestamp(time)
  return (date(time) - epoch):spanseconds()
end


local function extract_object(storage, obj)
  local node_id = obj.name:sub(#storage.election_prefix + 1)
  local register_time = get_timestamp(obj.timeCreated)
  local refreshed_time = get_timestamp(obj.updated)

  return {
    node_id = node_id,
    register_time = register_time,
    refreshed_time = refreshed_time,
  }
end


function _M:get_candidates()
  local res, err = gcp_call(storage_v1.objects.list, {
    bucket = self.bucket,
    prefix = self.election_prefix,
    maxResults = 1000, -- unlikely to have more than 1000 nodes
  })

  if not res then
    return nil, err .. " listing objects from bucket: " .. self.bucket .. " prefix: " .. self.election_prefix
  end

  local items = res.items

  if not items then
    return nil, "no items found"
  end

  -- emit a warning in this case
  if #items == 1000 then
    log(WARN, "too many objects in bucket: ", self.bucket, " prefix: ", self.election_prefix, " consider set a lifecycle rule to remove outdated objects")
  end

  local now = ngx_now()

  local item_iter, tbl, idx = ipairs(items)

  return function()
    -- return first fresh object if exists
    while true do
      local object
      idx, object = item_iter(tbl, idx)
      if not idx then
        return nil
      end

      local ok, registration = pcall(extract_object, self, object)

      if not ok then
        -- ignore incorrectly formatted object and continue
        log(WARN, "failed to extract a registration object: ", object.name)

      elseif self.election:is_fresh(registration.refreshed_time, now) then
        return registration
      end
    end
  end
end


return _M
