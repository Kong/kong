-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local meta = require "kong.meta"
local kube = require "kong.vaults.hcv.kube"
local utils = require "kong.tools.utils"
local cjson = require("cjson.safe").new()
local http = require "resty.luasocket.http"


local decode_json = cjson.decode
local encode_json = cjson.encode
local pairs = pairs
local type = type
local fmt = string.format
local log = ngx.log


local DEBUG = ngx.DEBUG
local ERR = ngx.ERR
local LOG_PREFIX = "[hcv] "


local function kube_vault_token_exchange(config)
  log(DEBUG, "no vault token in cache - getting one")

  local kube_role = config.kube_role or "default"
  log(DEBUG, LOG_PREFIX, "using kubernetes service account vault authentication mechanism for role: ", kube_role)

  -- get the current kube service account context JWT
  local kube_jwt, err = kube.get_service_account_token(config.kube_api_token_file)
  if err then
    log(ERR, LOG_PREFIX, "error loading kubernetes service account jwt from filesystem: ", err)
    return
  end

  -- exchange the jwt for a vault token
  local c = http.new()

  local kube_auth_path = config.kube_auth_path
  if kube_auth_path then
    kube_auth_path = kube_auth_path:gsub("^/", ""):gsub("/$", "")
  else
    kube_auth_path = "kubernetes"
  end

  local req_path = config.vault_host .. "/v1/auth/" .. kube_auth_path .. "/login"
  local req_data = {
    jwt = kube_jwt,
    role = kube_role,
  }

  local res, err = c:request_uri(req_path, {
    -- add a namespace to authenticate to, else use root.
    headers = {
      ["X-Vault-Namespace"] = config.auth_namespace or "root",
    },
    method = "POST",
    body = cjson.encode(req_data),
  })

  if err then
    log(ERR, LOG_PREFIX, "failure when exchanging kube service account jwt for vault token: ", err)
    return
  end

  if res.status ~= 200 then
    log(ERR, LOG_PREFIX, "invalid response code ", res.status, " received when exchanging kube service account jwt for vault token: ", res.body)
    return
  end

  -- capture the current token and ttl
  local vault_response = cjson.decode(res.body)
  return vault_response.auth.client_token, nil, vault_response.auth.lease_duration
end


local function get_vault_token(config)
  if config.auth_method == "token" then
    log(DEBUG, LOG_PREFIX, "using static env token vault authentication mechanism")
    return config.token

  elseif config.auth_method == "kubernetes" then
    local cache_key = fmt("vaults:credentials:hcv:%s:%s", config.vault_host, config.kube_role)

    local cache = kong.cache
    local token
    if cache then
      token = cache:get(cache_key, nil, kube_vault_token_exchange, config)
    else
      token = kube_vault_token_exchange(config)
    end

    if not token then
      if cache then
        cache:invalidate(cache_key)
      end
      return
    end

    return token
  end

  log(ERR, LOG_PREFIX, "vault authentication mechanism ", config.auth_method, " is not supported for hashicorp vault")
end


local function request(conf, resource, version, request_conf)
  local client, err = http.new()
  if not client then
    return nil, err
  end

  local request_opts = {
    headers = {
      ["X-Vault-Namespace"] = conf.namespace,
    },
    -- TODO: turned off because CLI does not currently support trusted certificates
    ssl_verify = false,
  }

  for k, v in pairs(request_conf or {}) do
    if type(v) == "table" then
      request[v] = utils.cycle_aware_deep_copy(v)
    else
      request_opts[k] = v
    end
  end

  local mount = (conf.mount or "secret"):gsub("^/", ""):gsub("/$", "")
  local protocol = conf.protocol or "http"
  local host = conf.host or "127.0.0.1"
  local port = conf.port or 8200

  local path
  if conf.kv == "v2" then
    if version then
      path = fmt("%s://%s:%d/v1/%s/data/%s?version=%d", protocol, host, port, mount, resource, version)
    else
      path = fmt("%s://%s:%d/v1/%s/data/%s", protocol, host, port, mount, resource)
    end

  else
    path = fmt("%s://%s:%d/v1/%s/%s", protocol, host, port, mount, resource)
  end

  local token_params = {
    token               = conf.token, -- pass this even though we know it already, for future compatibility
    auth_method         = conf.auth_method or "token",
    auth_namespace      = conf.namespace,
    vault_host          = fmt("%s://%s:%d", protocol, host, port),
    kube_api_token_file = conf.kube_api_token_file,
    kube_role           = conf.kube_role,
    kube_auth_path      = conf.kube_auth_path,
  }

  local token = get_vault_token(token_params)
  if not token then
    return nil, "no authentication mechanism worked for vault"
  end

  request_opts.headers["X-Vault-Token"] = token

  local res
  res, err = client:request_uri(path, request_opts)
  if err then
    return nil, err
  end

  local status = res.status
  if status == 404 then
    return nil, "not found"
  elseif status < 200 or status >= 300 then
    return nil, res.body
  else
    return res.body
  end
end


local function get(conf, resource, version)
  local secret, err = request(conf, resource, version)
  if not secret then
    return nil, fmt("unable to retrieve secret from vault: %s", err)
  end

  local json
  json, err = decode_json(secret)
  if type(json) ~= "table" then
    if err then
      return nil, fmt("unable to json decode value received from vault: %s, ", err)
    end

    return nil, fmt("unable to json decode value received from vault: invalid type (%s), table expected", type(json))
  end

  local data = json.data
  if type(data) ~= "table" then
    return nil, fmt("invalid data received from vault: invalid type (%s), table expected", type(data))
  end

  if conf.kv == "v2" then
    data = data.data
    if type(data) ~= "table" then
      return nil, fmt("invalid data (v2) received from vault: invalid type (%s), table expected", type(data))
    end
  end

  data, err = encode_json(data)
  if not data then
    return nil, fmt("unable to json encode data received from vault: %s", err)
  end

  return data
end


return {
  name = "hcv",
  VERSION = meta.core_version,
  get = get,
  get_vault_token = get_vault_token,
  _request = request,
  license_required = true,
}
