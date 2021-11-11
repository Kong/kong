-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local log           = require "kong.plugins.openid-connect.log"
local hash          = require "kong.openid-connect.hash"
local session       = require "resty.session"


local ipairs        = ipairs
local concat        = table.concat
local encode_base64 = ngx.encode_base64


local function new(args, secret)
  local initialized
  local strategy
  local storage
  local compressor
  local redis
  local memcache
  return function(options)
    if not initialized then
      strategy   = args.get_conf_arg("session_strategy", "default")
      storage    = args.get_conf_arg("session_storage", "cookie")
      compressor = args.get_conf_arg("session_compressor", "none")

      if not memcache and storage == "memcache" then
        log("loading configuration for memcache session storage")
        memcache = {
          uselocking = false,
          prefix     = args.get_conf_arg("session_memcache_prefix", "sessions"),
          socket     = args.get_conf_arg("session_memcache_socket"),
          host       = args.get_conf_arg("session_memcache_host", "127.0.0.1"),
          port       = args.get_conf_arg("session_memcache_port", 11211),
        }

      elseif not redis and storage == "redis" then
        log("loading configuration for redis session storage")
        local cluster_nodes = args.get_conf_arg("session_redis_cluster_nodes")
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
            uselocking      = false,
            prefix          = args.get_conf_arg("session_redis_prefix", "sessions"),
            auth            = args.get_conf_arg("session_redis_auth"),
            connect_timeout = args.get_conf_arg("session_redis_connect_timeout"),
            cluster         = {
              nodes           = cluster_nodes,
              name            = "redis-cluster:" .. hashed_name,
              dict            = "kong_locks",
              maxredirections = args.get_conf_arg("session_redis_cluster_maxredirections"),
            }
          }

        else
          redis = {
            uselocking      = false,
            prefix          = args.get_conf_arg("session_redis_prefix", "sessions"),
            socket          = args.get_conf_arg("session_redis_socket"),
            host            = args.get_conf_arg("session_redis_host", "127.0.0.1"),
            port            = args.get_conf_arg("session_redis_port", 6379),
            auth            = args.get_conf_arg("session_redis_auth"),
            connect_timeout = args.get_conf_arg("session_redis_connect_timeout"),
            read_timeout    = args.get_conf_arg("session_redis_read_timeout"),
            send_timeout    = args.get_conf_arg("session_redis_send_timeout"),
            ssl             = args.get_conf_arg("session_redis_ssl", false),
            ssl_verify      = args.get_conf_arg("session_redis_ssl_verify", false),
            server_name     = args.get_conf_arg("session_redis_server_name"),
          }
        end
      end

      initialized = true
    end

    options.strategy   = strategy
    options.storage    = storage
    options.memcache   = memcache
    options.compressor = compressor
    options.redis      = redis
    options.secret     = secret

    log("trying to open session using cookie named '", options.name, "'")
    return session.open(options)
  end
end


return {
  new = new
}
