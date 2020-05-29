local log     = require "kong.plugins.openid-connect.log"
local session = require "resty.session"


local function new(args, secret)
  local initialized
  local strategy
  local storage
  local redis
  local memcache
  return function(options)
    if not initialized then
      strategy = args.get_conf_arg("session_strategy", "default")
      storage  = args.get_conf_arg("session_storage", "cookie")

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
          redis = {
            uselocking      = false,
            prefix          = args.get_conf_arg("session_redis_prefix", "sessions"),
            auth            = args.get_conf_arg("session_redis_auth"),
            connect_timeout = args.get_conf_arg("session_redis_connect_timeout"),
            cluster         = {
              nodes           = cluster_nodes,
              name            = "redis-cluster",
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

    options.strategy = strategy
    options.storage  = storage
    options.memcache = memcache
    options.redis    = redis
    options.secret   = secret

    log("trying to open session using cookie named '", options.name, "'")
    return session.open(options)
  end
end


return {
  new = new
}
