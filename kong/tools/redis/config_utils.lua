-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local digest = require "resty.openssl.digest"


local ngx = ngx
local ERR = ngx.ERR
local WARN = ngx.WARN
local DEBUG = ngx.DEBUG
local ngx_log = ngx.log
local ngx_null = ngx.null
local encode_base64 = ngx.encode_base64


local DIGEST_SHA256_NAME = "sha256"


local gen_poolname
do
  local password_cache = {}

  local function hash_password(password)
    if not password then
      return
    end

    local encoded_password = encode_base64(password, true)
    local hashed_password = password_cache[encoded_password]
    if hashed_password then
      return hashed_password
    end

    local digest_obj, err = digest.new(DIGEST_SHA256_NAME)
    if not digest_obj then
      ngx_log(ERR, "unable to initialize digest: ", err)
      return nil, err
    end

    local ok
    ok, err = digest_obj:update(password)
    if not ok then
      ngx_log(ERR, "unable to update digest: ", err)
      return nil, err
    end

    hashed_password, err = digest_obj:final()
    if not hashed_password then
      ngx_log(ERR, "unable to hash password: ", err)
      return nil, err
    end

    hashed_password = encode_base64(hashed_password, true)
    password_cache[encoded_password] = hashed_password

    return hashed_password
  end

  local function is_present(value)
    if value == nil or value == ngx_null then
      return false
    end

    if type(value) == "number" and value ~= value then
      return false -- NaN
    end

    if type(value) == "string" and value == "" then
      return false
    end

    if type(value) == "table" then
      return next(value) ~= nil
    end

    return true
  end

  gen_poolname = function(conf)
    if not is_present(conf) then
      ngx_log(ERR, "conf is unset, fallback to default pool")
      return
    end

    if is_present(conf.sentinel_nodes) then
      ngx_log(DEBUG, "sentinel_nodes is set, fallback to default pool")
      return
    end

    if is_present(conf.cluster_nodes) then
      ngx_log(DEBUG, "cluster_nodes is set, fallback to default pool")
      return
    end

    local host = conf.host
    local port = conf.port
    local socket = conf.socket
    if is_present(socket) then
      -- prioritize socket over host as 'host' and 'port' have default values in the schema
      ngx_log(WARN, "both host and socket are set, prioritize socket")
      host = nil
      port = nil

    elseif is_present(host) then
      if not is_present(port) then
        ngx_log(DEBUG, "port is unset, fallback to default pool")
        return
      end

    else
      ngx_log(DEBUG, "neither host nor socket is set, fallback to default pool")
      return
    end

    local ssl = conf.ssl
    local ssl_verify = conf.ssl_verify
    local server_name = conf.server_name
    if not is_present(ssl) then
      ngx_log(DEBUG, "ssl is unset, fallback to default pool")
      return
    end
    if not is_present(ssl_verify) then
      ngx_log(DEBUG, "ssl_verify is unset, fallback to default pool")
      return
    end
    if ssl_verify == true and ssl ~= true then
      ngx_log(DEBUG, "ssl_verify is true but ssl is not true, fallback to default pool")
      return
    end
    if ssl_verify == true and not is_present(server_name) then
      ngx_log(DEBUG, "ssl_verify is true but server_name is unset, fallback to default pool")
      return
    end

    local database = conf.database
    if not is_present(database) then
      ngx_log(DEBUG, "database is unset, fallback to default pool")
      return
    end

    local hashed_password, err = hash_password(conf.password)
    if err then
      ngx_log(ERR, "unable to create password hash: ", err, ", fallback to default pool")
      return
    end

    return (host or "")
           .. ":" .. tostring(port or "")
           .. ":" .. (socket or "")
           .. ":" .. tostring(ssl)
           .. ":" .. tostring(ssl_verify)
           .. ":" .. (server_name or "")
           .. ":" .. (conf.username or "")
           .. ":" .. (hashed_password or "")
           .. ":" .. tostring(conf.database)

  end
end


return {
  gen_poolname = gen_poolname,
}