-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local resty_mlcache = require "kong.resty.mlcache"
local pl_file = require "pl.file"
local cjson = require("cjson.safe").new()
local http = require "resty.luasocket.http"

local fmt = string.format
local log = ngx.log

local DEBUG = ngx.DEBUG
local ERR = ngx.ERR
local LOG_PREFIX = "[hcv] "


-- Using a single mlcache instead of kong cache since kong cache can
-- be purged anytime, and response wrapping callback can only be called
-- once on each token.
local shm_name = "kong_vaults_hcv"
local cache_name = "kong_vaults_hcv_approle_secret_id_cache"
local secret_id_mlcache = resty_mlcache.new(cache_name, shm_name, {
  shm_locks = "kong_locks",
  resty_lock_opts = {
    exptime = 10,
    timeout = 5,
  },
  lru_size = 1000,
})


local function get_secret_id_file(file)
  return pl_file.read(file):gsub("\n", "")
end


local function cache_key(config)
  return fmt("vaults:credentials:%s:%s:%s:%s:%s:%s:%s",
             config.vault_host,
             config.auth_method,
             config.approle_auth_path,
             config.approle_role_id,
             config.approle_secret_id,
             config.approle_secret_id_file,
             config.approle_response_wrapping)
end


local function response_wrapping_cache_key(response_wrapping_token)
  return fmt("vaults:responsewrapping:%s",
             response_wrapping_token)
end


local function unwrapping_secret_id(response_wrapping_token, config)
  log(DEBUG, LOG_PREFIX, "unwrapping secret id for approle authentication")
  local c = http.new()
  local req_path = config.vault_host .. "/v1/sys/wrapping/unwrap"
  local res, err = c:request_uri(req_path, {
    -- add a namespace to authenticate to, else use root.
    headers = {
      ["X-Vault-Namespace"] = config.auth_namespace or "root",
      ["X-Vault-Token"] = response_wrapping_token,
    },
    method = "POST",
  })

  if err then
    log(ERR, LOG_PREFIX, "failure when unwrapping approle secret_id for vault token: ", err)
    return nil, err, -1
  end

  if res.status ~= 200 then
    log(ERR, LOG_PREFIX, "invalid response code ", res.status, " received when unwrapping approle secret_id for vault token: ", res.body)
    return nil, res.body, -1
  end

  local vault_response = cjson.decode(res.body)
  log(DEBUG, LOG_PREFIX, "unwrapping succeed, ", vault_response.data.secret_id, ", TTL:", vault_response.data.secret_id_ttl)
  return vault_response.data.secret_id, nil, vault_response.data.secret_id_ttl
end


local function unwrapping_secret_id_by_cache(response_wrapping_token, config)
  local secret_id_cache_key = response_wrapping_cache_key(response_wrapping_token)
  local secret_id, err = secret_id_mlcache:get(secret_id_cache_key, nil, unwrapping_secret_id, response_wrapping_token, config)
  if err then
    log(ERR, LOG_PREFIX, "error loading approle secret_id from cache: ", err)
    return
  end

  return secret_id
end


local function fetch_role_and_secret(config)
  local approle_role_id = config.approle_role_id
  if not approle_role_id then
    log(ERR, LOG_PREFIX, "no approle role_id specified")
    return
  end
  log(DEBUG, LOG_PREFIX, fmt("using approle vault authentication mechanism for role: %s, response_wrapping: %s", approle_role_id, config.approle_response_wrapping))

  local approle_secret_id, err do
    if config.approle_secret_id then
      approle_secret_id = config.approle_secret_id

    elseif config.approle_secret_id_file then
      approle_secret_id, err = get_secret_id_file(config.approle_secret_id_file)
      if err then
        log(ERR, LOG_PREFIX, "error loading approle secret_id from filesystem: ", err)
        return
      end

    else
      log(ERR, LOG_PREFIX, "no approle secret_id or secret_id_file specified")
      return
    end

    -- If response wrapping is enabled, then the configured secret_id is
    -- actually a wrapping token and we need to unwrap it to get the real the secret_id
    -- Note that unwrapping can only be done once on each token so we need to cache
    -- the unwrapped secret_id by its TTL.
    if config.approle_response_wrapping then
      approle_secret_id = unwrapping_secret_id_by_cache(approle_secret_id, config)
      if not approle_secret_id then
        log(ERR, LOG_PREFIX, "failed to unwrap approle secret_id")
        return
      end
    end
  end

  return approle_role_id, approle_secret_id
end


local function approle_vault_token_exchange(config)
  local approle_role_id, approle_secret_id = fetch_role_and_secret(config)
  if not approle_role_id or not approle_secret_id then
    return
  end

  local approle_auth_path = (config.approle_auth_path or "approle"):gsub("^/", ""):gsub("/$", "")

  local req_path = config.vault_host .. "/v1/auth/" .. approle_auth_path .. "/login"
  local req_data = {
    role_id = approle_role_id,
    secret_id = approle_secret_id,
  }

  local c = http.new()
  local res, err = c:request_uri(req_path, {
    -- add a namespace to authenticate to, else use root.
    headers = {
      ["X-Vault-Namespace"] = config.auth_namespace or "root",
    },
    method = "POST",
    body = cjson.encode(req_data),
  })

  if err then
    log(ERR, LOG_PREFIX, "failure when calling approle login for vault token: ", err)
    return
  end

  if res.status ~= 200 then
    log(ERR, LOG_PREFIX, "invalid response code ", res.status, " received when calling approle login for vault token: ", res.body)
    return
  end

  local vault_response = cjson.decode(res.body)
  return vault_response.auth.client_token, nil, vault_response.auth.lease_duration
end


return {
  cache_key = cache_key,
  get_secret_id_file = get_secret_id_file,
  vault_token_exchange = approle_vault_token_exchange,
}
