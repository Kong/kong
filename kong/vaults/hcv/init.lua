-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local meta = require "kong.meta"
local kube = require "kong.vaults.hcv.kube"
local cjson = require("cjson.safe").new()
local http = require "resty.luasocket.http"


local decode_json = cjson.decode
local encode_json = cjson.encode
local type = type
local byte = string.byte
local sub = string.sub
local fmt = string.format


local SLASH = byte("/")


local REQUEST_OPTS = {
  headers = {
    ["X-Vault-Token"] = ""
  },
  -- TODO: turned off because CLI does not currently support trusted certificates
  ssl_verify = false,
}


local function kube_vault_token_exchange(config)
  kong.log.debug("no vault token in cache - getting one")

  local kube_role = config.kube_role or "default"
  ngx.log(ngx.DEBUG, "using kubernetes serviceaccount vault authentication mechanism for role: ", kube_role)

  -- get the current kube serviceaccount context JWT
  local kube_jwt, err = kube.get_service_account_token(config.kube_api_token_file)
  if err then
    ngx.log(ngx.ERR, "error loading kubernetes serviceaccount jwt from filesystem: ", err)
    return nil, nil, nil
  end

  -- exchange the jwt for a vault token
  local c = http.new()

  local req_path = config.vault_host .. "/v1/auth/kubernetes/login"
  local req_data = {
    ["jwt"] = kube_jwt,
    ["role"] = kube_role,
  }

  local res, err = c:request_uri(req_path, {
    method = "POST",
    body = cjson.encode(req_data),
  })

  if err then
    ngx.log(ngx.ERR, "failure when exchanging kube serviceaccount jwt for vault token: ", err)
    return nil, nil, nil
  end

  if res.status ~= 200 then
    ngx.log(ngx.ERR, "invalid response code ", res.status, " received when exchanging kube serviceaccount jwt for vault token: ", res.body)
    return nil, nil, nil
  end

  -- capture the current token and ttl
  local vault_response = cjson.decode(res.body)
  return vault_response.auth.client_token, nil, vault_response.auth.lease_duration
end


local function get_vault_token(config)
  if config.auth_method == "token" then
    ngx.log(ngx.DEBUG, "using static env token vault authentication mechanism")
    return config.token, nil

  elseif config.auth_method == "kubernetes" then
    local cache_key = fmt("vaults:credentials:hcv:%s:%s", config.vault_host, config.kube_role)

    local token
    if kong.cache then
      token = kong.cache:get(cache_key, nil, kube_vault_token_exchange, config)
    else
      token = kube_vault_token_exchange(config)
    end

    if not token then
      kong.cache:invalidate(cache_key)
      return nil, nil
    end

    return token, nil
  end

  ngx.log(ngx.ERR, "vault authentication mechanism ", config.auth_method, " is not supported for hashicorp vault")
  return nil, nil
end


local function request(conf, resource, version)
  local client, err = http.new()
  if not client then
    return nil, err
  end

  local mount = conf.mount
  if mount then
    if byte(mount, 1, 1) == SLASH then
      if byte(mount, -1) == SLASH then
        mount = sub(mount, 2, -2)
      else
        mount = sub(mount, 2)
      end

    elseif byte(mount, -1) == SLASH then
      mount = sub(mount, 1, -2)
    end

  else
    mount = "secret"
  end

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

  REQUEST_OPTS.headers["X-Vault-Namespace"] = conf.namespace

  local token_params = {
    ["token"]               = conf.token, -- pass this even though we know it already, for future compatibility
    ["auth_method"]         = conf.auth_method or "token",
    ["vault_host"]          = fmt("%s://%s:%d", protocol, host, port),
    ["kube_api_token_file"] = conf.kube_api_token_file,
    ["kube_role"]           = conf.kube_role,
  }

  -- check kong.cache is nil so that we can run from CLI mode
  local token = get_vault_token(token_params)
  if not token then
    return false, "no authentication mechanism worked for vault"
  end


  REQUEST_OPTS.headers["X-Vault-Token"] = token

  local res

  res, err = client:request_uri(path, REQUEST_OPTS)
  if err then
    return nil, err
  end

  local status = res.status
  if status == 404 then
    return nil, "not found"
  elseif status ~= 200 then
    return nil, fmt("invalid status code (%d), 200 was expected", res.status)
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
  license_required = true,
}
