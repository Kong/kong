local http = require "resty.http"
local cjson = require "cjson.safe"
local resty_sha256 = require "resty.sha256"
local keyring = require "kong.keyring"


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
    return false, "invalid response"
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


function _M.sync(token)
  local config = kong.configuration
  local host = config.keyring_vault_host
  local mount = config.keyring_vault_mount
  local path = config.keyring_vault_path

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

  return true
end


function _M.init_worker(config)
  if ngx.worker.id() ~= 0 then
    return
  end

  ngx.timer.at(0, function()
    local ok, err = _M.sync(config.keyring_vault_token)
    if not ok then
      ngx.log(ngx.ERR, _log_prefix, "error syncing vault tokens: ", err)
    end
  end)
end


return _M
