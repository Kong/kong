-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local log           = require "kong.plugins.saml.log"
local hash          = require "kong.openid-connect.hash"
local session       = require "resty.session"


local ipairs        = ipairs
local concat        = table.concat
local encode_base64 = ngx.encode_base64


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
        local cluster_nodes = conf["session_redis_cluster_nodes"]
        if cluster_nodes then
          local n = 0
          local name = {}
          for _, node in ipairs(cluster_nodes) do
            name[n+1] = node.ip   or "127.0.0.1"
            name[n+2] = ":"
            name[n+3] = node.port or 6379
            n = n + 3
          end

          local hashed_name = encode_base64(hash.S256(concat(name, ";", 1, n)), true)

          redis = {
            prefix           = conf["session_redis_prefix"],
            username         = conf["session_redis_username"],
            password         = conf["session_redis_password"],
            connect_timeout  = conf["session_redis_connect_timeout"],
            read_timeout     = conf["session_redis_read_timeout"],
            send_timeout     = conf["session_redis_send_timeout"],
            ssl              = conf["session_redis_ssl"] or false,
            ssl_verify       = conf["session_redis_ssl_verify"] or false,
            server_name      = conf["session_redis_server_name"],
            name             = "redis-cluster:" .. hashed_name,
            nodes            = cluster_nodes,
            lock_zone        = "kong_locks",
            max_redirections = conf["session_redis_cluster_max_redirections"] or
                               conf["session_redis_cluster_maxredirections"],
          }

        else
          redis = {
            prefix          = conf["session_redis_prefix"],
            socket          = conf["session_redis_socket"],
            host            = conf["session_redis_host"],
            port            = conf["session_redis_port"],
            username        = conf["session_redis_username"],
            password        = conf["session_redis_password"],
            connect_timeout = conf["session_redis_connect_timeout"],
            read_timeout    = conf["session_redis_read_timeout"],
            send_timeout    = conf["session_redis_send_timeout"],
            ssl             = conf["session_redis_ssl"] or false,
            ssl_verify      = conf["session_redis_ssl_verify"] or false,
            server_name     = conf["session_redis_server_name"],
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
