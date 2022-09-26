-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local http = require "resty.http"
local cjson = require "cjson.safe"
local resty_sha256 = require "resty.sha256"
local keyring = require "kong.keyring"
local pl_file = require "pl.file"


local _M = {}


local _log_prefix = "[keyring vault] "


function _M.init(config)
  -- nop
end


local function fetch_versions(host, mount, path, token)
  local c = http.new()

  local req_path = host .. "/v1/" .. mount .. "/metadata/" .. path

  local res, err = c:request_uri(req_path, {
    headers = {
      ["X-Vault-Token"] = token
    }
  })
  if err then
    return false, err
  end

  if res.status ~= 200 then
    return false, "invalid response code when fetching keyring secret versions: " .. res.status
  end

  local vault_res = cjson.decode(res.body)
  local versions = vault_res.data.versions
  local t = {}

  for k, v in pairs(versions) do
    if not v.destroyed then
      table.insert(t, k)
    end
  end

  if #t == 0 then
    return false, "no metadata found"
  end

  return { current = vault_res.data.current_version, versions = t }
end


local function fetch_data(host, mount, path, token, version_data)
  local c = http.new()

  local req_path = host .. "/v1/" .. mount .. "/data/" .. path

  local keys = {}

  for _, version in ipairs(version_data.versions) do
    local res, err = c:request_uri(req_path .. "?version=" .. version, {
      headers = {
        ["X-Vault-Token"] = token
      }
    })
    if err then
      return false, err
    end

    if res.status ~= 200 then
      return false, "invalid response"
    end

    local vault_res = cjson.decode(res.body)
    local data = vault_res.data

    assert(data.metadata.version == tonumber(version))

    if data.data.id and data.data.key then
      table.insert(keys, {
        id = data.data.id,
        key = data.data.key,
        current = data.metadata.version == version_data.current,
      })
    end
  end

  return keys
end


local function get_vault_token(config)
  local token = nil

  if config.keyring_vault_auth_method == "token" then
    ngx.log(ngx.DEBUG, "using static env token vault authentication mechanism")
    return config.keyring_vault_token

  elseif config.keyring_vault_auth_method == "kubernetes" then
    ngx.log(ngx.DEBUG, "using kubernetes serviceaccount vault authentication mechanism for role: ", config.keyring_vault_kube_role)

    -- get the kubernetes serviceaccount jwt
    local kube_jwt, err = pl_file.read(config.keyring_vault_kube_api_token_file)
    if err then
      ngx.log(ngx.ERR, "error loading kubernetes serviceaccount jwt from filesystem: ", err)
      return nil
    end

    -- exchange the jwt for a vault token
    local c = http.new()

    local req_path = config.keyring_vault_host .. "/v1/auth/kubernetes/login"
    local req_data = {
      ["jwt"] = kube_jwt,
      ["role"] = config.keyring_vault_kube_role,
    }

    local res, err = c:request_uri(req_path, {
      method = "POST",
      body = cjson.encode(req_data),
    })

    if err then
      ngx.log(ngx.ERR, _log_prefix, "failure when exchanging kube serviceaccount jwt for vault token: ", err)
      return nil
    end

    if res.status ~= 200 then
      ngx.log(ngx.ERR, _log_prefix, "invalid response code when exchanging kube serviceaccount jwt for vault token: ", res.status)
      return nil
    end

    -- capture the current token
    local vault_response = cjson.decode(res.body)
    return vault_response.auth.client_token
  end

  ngx.log(ngx.ERR, _log_prefix, "vault authentication mechanism ", config.keyring_vault_auth_method, " is not supported for keyring")
  return nil
end


function _M.sync(token)
  local config = kong.configuration
  local host = config.keyring_vault_host
  local mount = config.keyring_vault_mount
  local path = config.keyring_vault_path

  local token = token or get_vault_token(config)
  if not token then
    return false, "no authentication mechanism worked for vault"
  end

  local versions, err = fetch_versions(host, mount, path, token)
  if not versions then
    return false, err
  end

  local keys, err = fetch_data(host, mount, path, token, versions)
  if not keys then
    return false, err
  end

  for _, entry in ipairs(keys) do
    local sha256 = resty_sha256:new()
    sha256:update(entry.key)
    local bytes = sha256:final()

    keyring.keyring_add(entry.id, bytes)

    if entry.current then
      keyring.activate_local(entry.id)
    end
  end

  keyring.invalidate_cache()

  return true
end


function _M.init_worker(config)
  if ngx.worker.id() ~= 0 then
    return
  end

  ngx.timer.at(0, function()
    -- nil arg call to sync() will cause it to iterate through
    -- the "get token" methods in the authentication chain
    local ok, err = _M.sync(nil)
    
    if not ok then
      ngx.log(ngx.ERR, _log_prefix, "error syncing vault tokens: ", err)
    end
  end)
end


return _M
