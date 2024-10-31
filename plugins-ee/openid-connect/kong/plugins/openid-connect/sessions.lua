-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local log           = require "kong.plugins.openid-connect.log"
local hash          = require "kong.openid-connect.hash"
local session       = require "resty.session"
local map           = require "pl.tablex".map


local ngx_null = ngx.null
local concat        = table.concat
local encode_base64 = ngx.encode_base64

local function is_present(x)
  return x and ngx_null ~= x
end

local function is_redis_cluster(redis)
  return is_present(redis.cluster_nodes)
end

local function is_redis_sentinel(redis)
  return is_present(redis.sentinel_nodes)
end


local function new(args, secret)
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
      audience = args.get_conf_arg("session_audience", "default")
      store_metadata = args.get_conf_arg("session_store_metadata", false)
      enforce_same_subject = args.get_conf_arg("session_enforce_same_subject", false)
      hash_subject = args.get_conf_arg("session_hash_subject", false)
      hash_storage_key = args.get_conf_arg("session_hash_storage_key", false)
      storage = args.get_conf_arg("session_storage", "cookie")

      if not memcached and (storage == "memcached" or storage == "memcache") then
        log("loading configuration for memcache session storage")
        storage = "memcached"
        memcached = {
          prefix = args.get_conf_arg("session_memcached_prefix")
                or args.get_conf_arg("session_memcache_prefix"),
          socket = args.get_conf_arg("session_memcached_socket")
                or args.get_conf_arg("session_memcache_socket"),
          host   = args.get_conf_arg("session_memcached_host")
                or args.get_conf_arg("session_memcache_host"),
          port   = args.get_conf_arg("session_memcached_port")
                or args.get_conf_arg("session_memcache_port"),
        }

      elseif not redis and storage == "redis" then
        log("loading configuration for redis session storage")
        local redis_conf = args.get_conf_arg("redis")
        if is_redis_cluster(redis_conf) then
          local cluster_addresses = map(function(node)
            return string.format("%s:%s", node.ip, tostring(node.port))
          end, redis_conf["cluster_nodes"])
          local cluster_name = concat(cluster_addresses, ";", 1, #cluster_addresses)

          local hashed_name = encode_base64(hash.S256(cluster_name), true)

          redis = {
            prefix            = redis_conf["prefix"],
            username          = redis_conf["username"],
            password          = redis_conf["password"],
            connect_timeout   = redis_conf["connect_timeout"],
            read_timeout      = redis_conf["read_timeout"],
            send_timeout      = redis_conf["send_timeout"],
            pool_size         = redis_conf["keepalive_pool_size"],
            backlog           = redis_conf["keepalive_backlog"],
            ssl               = redis_conf["ssl"] or false,
            ssl_verify        = redis_conf["ssl_verify"] or false,
            server_name       = redis_conf["server_name"],
            name              = "redis-cluster:" .. hashed_name,
            nodes             = redis_conf["cluster_nodes"],
            lock_zone         = "kong_locks",
            max_redirections  = redis_conf["cluster_max_redirections"]
                            or args.get_conf_arg("session_redis_cluster_maxredirections"),
          }

          elseif is_redis_sentinel(redis_conf)  then
            redis = {
              master            = redis_conf["sentinel_master"],
              role              = redis_conf["sentinel_role"],
              sentinels         = redis_conf["sentinel_nodes"],
              socket            = redis_conf["socket"],
              sentinel_username = redis_conf["username"],
              sentinel_password = redis_conf["password"],
              database          = redis_conf["database"],
              prefix            = redis_conf["prefix"],
              connect_timeout   = redis_conf["connect_timeout"],
              read_timeout      = redis_conf["read_timeout"],
              send_timeout      = redis_conf["send_timeout"],
              pool_size         = redis_conf["keepalive_pool_size"],
              backlog           = redis_conf["keepalive_backlog"],
              ssl               = redis_conf["ssl"] or false,
              ssl_verify        = redis_conf["ssl_verify"] or false,
              server_name       = redis_conf["server_name"],
            }
          else
            redis = {
              prefix            = redis_conf["prefix"],
              socket            = redis_conf["socket"],
              host              = redis_conf["host"],
              port              = redis_conf["port"],
              username          = redis_conf["username"],
              password          = redis_conf["password"],
              database          = redis_conf["database"],
              connect_timeout   = redis_conf["connect_timeout"],
              read_timeout      = redis_conf["read_timeout"],
              send_timeout      = redis_conf["send_timeout"],
              pool_size         = redis_conf["keepalive_pool_size"],
              backlog           = redis_conf["keepalive_backlog"],
              ssl               = redis_conf["ssl"] or false,
              ssl_verify        = redis_conf["ssl_verify"] or false,
              server_name       = redis_conf["server_name"],
            }
          end
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
