-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local log           = require "kong.plugins.saml.log"
local hash          = require "kong.openid-connect.hash"
local session       = require "resty.session"
local map           = require "pl.tablex".map
local redis_config_utils = require "kong.tools.redis.config_utils"


local ngx_null = ngx.null
local concat        = table.concat
local encode_base64 = ngx.encode_base64
local gen_poolname  = redis_config_utils.gen_poolname


local function is_present(x)
  return x and ngx_null ~= x
end

local function is_redis_cluster(redis)
  return is_present(redis.cluster_nodes)
end

local function is_redis_sentinel(redis)
  return is_present(redis.sentinel_nodes)
end

local function new(conf, secret)
  local initialized
  local storage
  local redis
  local memcached
  local audience
  local store_metadata
  local enforce_same_subject
  local hash_subject
  local hash_storage_key
  return function(options)
    if not initialized then
      audience = conf["session_audience"] or "default"
      store_metadata = conf["session_store_metadata"] or false
      enforce_same_subject = conf["session_enforce_same_subject"] or false
      hash_subject = conf["session_hash_subject"] or false
      hash_storage_key = conf["session_hash_storage_key"] or false
      storage = conf["session_storage"] or "cookie"

      if not memcached and (storage == "memcached" or storage == "memcache") then
        log("loading configuration for memcache session storage")
        storage = "memcached"
        memcached = {
          prefix = conf["session_memcached_prefix"] or conf["session_memcache_prefix"],
          socket = conf["session_memcached_socket"] or conf["session_memcache_socket"],
          host   = conf["session_memcached_host"]   or conf["session_memcache_host"],
          port   = conf["session_memcached_port"]   or conf["session_memcache_port"],
        }

      elseif not redis and storage == "redis" then
        log("loading configuration for redis session storage")
        if is_redis_cluster(conf.redis) then
          local cluster_addresses = map(function(node)
            return string.format("%s:%s", node.ip, tostring(node.port))
          end, conf.redis["cluster_nodes"])
          local cluster_name = concat(cluster_addresses, ";", 1, #cluster_addresses)

          local hashed_name = encode_base64(hash.S256(cluster_name), true)

          redis = {
            prefix            = conf.redis["prefix"],
            username          = conf.redis["username"],
            password          = conf.redis["password"],
            connect_timeout   = conf.redis["connect_timeout"],
            read_timeout      = conf.redis["read_timeout"],
            send_timeout      = conf.redis["send_timeout"],
            pool_size         = conf.redis["keepalive_pool_size"],
            backlog           = conf.redis["keepalive_backlog"],
            ssl               = conf.redis["ssl"] or false,
            ssl_verify        = conf.redis["ssl_verify"] or false,
            server_name       = conf.redis["server_name"],
            name              = "redis-cluster:" .. hashed_name,
            nodes             = conf.redis["cluster_nodes"],
            lock_zone         = "kong_locks",
            max_redirections  = conf.redis["cluster_max_redirections"] or
                                conf["session_redis_cluster_maxredirections"],
          }

        elseif is_redis_sentinel(conf.redis)  then
          redis = {
            master            = conf.redis["sentinel_master"],
            role              = conf.redis["sentinel_role"],
            sentinels         = conf.redis["sentinel_nodes"],
            socket            = conf.redis["socket"],
            sentinel_username = conf.redis["username"],
            sentinel_password = conf.redis["password"],
            database          = conf.redis["database"],
            prefix            = conf.redis["prefix"],
            connect_timeout   = conf.redis["connect_timeout"],
            read_timeout      = conf.redis["read_timeout"],
            send_timeout      = conf.redis["send_timeout"],
            pool_size         = conf.redis["keepalive_pool_size"],
            backlog           = conf.redis["keepalive_backlog"],
            ssl               = conf.redis["ssl"] or false,
            ssl_verify        = conf.redis["ssl_verify"] or false,
            server_name       = conf.redis["server_name"],
          }
        else
          redis = {
            prefix            = conf.redis["prefix"],
            socket            = conf.redis["socket"],
            host              = conf.redis["host"],
            port              = conf.redis["port"],
            username          = conf.redis["username"],
            password          = conf.redis["password"],
            connect_timeout   = conf.redis["connect_timeout"],
            read_timeout      = conf.redis["read_timeout"],
            send_timeout      = conf.redis["send_timeout"],
            pool_size         = conf.redis["keepalive_pool_size"],
            backlog           = conf.redis["keepalive_backlog"],
            ssl               = conf.redis["ssl"] or false,
            ssl_verify        = conf.redis["ssl_verify"] or false,
            server_name       = conf.redis["server_name"],
          }
        end

        redis.pool = gen_poolname(redis)
      end

      initialized = true
    end

    options.storage              = storage
    options.memcached            = memcached
    options.redis                = redis
    options.audience             = audience
    options.store_metadata       = store_metadata
    options.enforce_same_subject = enforce_same_subject
    options.hash_subject         = hash_subject
    options.hash_storage_key     = hash_storage_key
    options.secret               = secret

    log("trying to open session using cookie named '", options.cookie_name, "'")
    return session.open(options)
  end
end


return {
  new = new
}
