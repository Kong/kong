-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Kong helpers for Redis integration; includes EE-only
-- features, such as Sentinel compatibility.


local typedefs           = require "kong.db.schema.typedefs"
local utils              = require "kong.tools.utils"
local map                = require "pl.tablex".map
local redis_config_utils = require "kong.enterprise_edition.tools.redis.v2.config_utils"

local DEFAULT_TIMEOUT = 2000
local MAX_INT = 2^31 - 2
local ngx_null = ngx.null


local function is_present(x)
  return x and ngx_null ~= x
end

local function validate_addresses(addresses)
  for _, address in ipairs(addresses) do
    local parts = utils.split(address, ":")

    if not (#parts == 2 and tonumber(parts[2])) then
      return false, "Invalid Redis host address: " .. address
    end
  end

  return true
end


return {
  type = "record",

  fields = {
    { host = typedefs.host { default = "127.0.0.1" } },
     -- the port is only used when the host is set.
     -- The default value is not used when other strategies are used so we do not do the mutual exclusion check for it
    { port = typedefs.port { default = 6379 } },
    { connect_timeout = typedefs.timeout { default = DEFAULT_TIMEOUT } },
    { send_timeout = typedefs.timeout { default = DEFAULT_TIMEOUT } },
    { read_timeout = typedefs.timeout { default = DEFAULT_TIMEOUT } },
    { username = { description = "Username to use for Redis connections. If undefined, ACL authentication won't be performed. This requires Redis v6.0.0+. To be compatible with Redis v5.x.y, you can set it to `default`.", type = "string",
        referenceable = true,
      } },
    { password = { description = "Password to use for Redis connections. If undefined, no AUTH commands are sent to Redis.", type = "string",
        encrypted = true,
        referenceable = true,
      } },
    { sentinel_username = { description = "Sentinel username to authenticate with a Redis Sentinel instance. If undefined, ACL authentication won't be performed. This requires Redis v6.2.0+.", type = "string",
        referenceable = true,
      } },
    { sentinel_password = { description = "Sentinel password to authenticate with a Redis Sentinel instance. If undefined, no AUTH commands are sent to Redis Sentinels.", type = "string",
        encrypted = true,
        referenceable = true,
      } },
    { database = { description = "Database to use for the Redis connection when using the `redis` strategy", type = "integer",
        default = 0,
      } },
    { keepalive_pool_size = { description = "The size limit for every cosocket connection pool associated with every remote server, per worker process. If neither `keepalive_pool_size` nor `keepalive_backlog` is specified, no pool is created. If `keepalive_pool_size` isn't specified but `keepalive_backlog` is specified, then the pool uses the default value. Try to increase (e.g. 512) this value if latency is high or throughput is low.", type = "integer",
        default = 256,
        between = { 1, MAX_INT },
      } },
    { keepalive_backlog = { description = "Limits the total number of opened connections for a pool. If the connection pool is full, connection queues above the limit go into the backlog queue. If the backlog queue is full, subsequent connect operations fail and return `nil`. Queued operations (subject to set timeouts) resume once the number of connections in the pool is less than `keepalive_pool_size`. If latency is high or throughput is low, try increasing this value. Empirically, this value is larger than `keepalive_pool_size`.",
        type = "integer",
        between = { 0, MAX_INT },
      } },
    { sentinel_master = { description = "Sentinel master to use for Redis connections. Defining this value implies using Redis Sentinel.",
        type = "string",
      } },
    { sentinel_role = { description = "Sentinel role to use for Redis connections when the `redis` strategy is defined. Defining this value implies using Redis Sentinel.",
        type = "string",
        one_of = { "master", "slave", "any" },
      } },
    { sentinel_nodes = { description = "Sentinel node addresses to use for Redis connections when the `redis` strategy is defined. Defining this field implies using a Redis Sentinel. The minimum length of the array is 1 element.",
      required = false,
      type = "array",
      len_min = 1,
      elements = {
        type = "record",
        fields = {
          { host = typedefs.host { required = true, default  = "127.0.0.1", }, },
          { port = typedefs.port { default = 6379, }, },
        },
      },
      } },
    { cluster_nodes = { description = "Cluster addresses to use for Redis connections when the `redis` strategy is defined. Defining this field implies using a Redis Cluster. The minimum length of the array is 1 element.",
        required = false,
        type = "array",
        len_min = 1,
        elements = {
          type = "record",
          fields = {
            { ip = typedefs.host { required = true, default  = "127.0.0.1", }, },
            { port = typedefs.port { default = 6379, }, },
          },
        },
      } },
    { ssl = { description = "If set to true, uses SSL to connect to Redis.",
        type = "boolean",
        required = false,
        default = false,
      } },
    { ssl_verify = { description = "If set to true, verifies the validity of the server SSL certificate. If setting this parameter, also configure `lua_ssl_trusted_certificate` in `kong.conf` to specify the CA (or server) certificate used by your Redis server. You may also need to configure `lua_ssl_verify_depth` accordingly.",
        type = "boolean",
        required = false,
        default = false,
      } },
    { server_name = typedefs.sni { required = false } },
    { cluster_max_redirections = { description = "Maximum retry attempts for redirection.",
        required = false,
        default = 5,
        type = "integer",
      } },
    { connection_is_proxied = { description = "If the connection to Redis is proxied (e.g. Envoy), set it `true`. Set the `host` and `port` to point to the proxy address.",
        type = "boolean",
        required = false,
        default = false,
      } },
  },

  entity_checks = {
    {
      mutually_required = { "host", "port" },
    },
    {
      mutually_required = { "sentinel_master", "sentinel_role", "sentinel_nodes" },
    },
    {
      mutually_required = { "connect_timeout", "send_timeout", "read_timeout" },
    },
    { conditional = {
        if_field = "connection_is_proxied", if_match = { eq = true },
        then_field = "host",                then_match = { required = true },
      }
    },
    {
      custom_entity_check = {
        field_sources = { "database", "connection_is_proxied" },
        run_with_missing_fields = true,
        fn = function(entity)
          local database = entity.database
          local connection_is_proxied = entity.connection_is_proxied

          if is_present(database) and database ~= 0 and connection_is_proxied == true then
            return nil, "database must be '0' or 'null' when 'connection_is_proxied' is 'true'."
          end

          return true
        end
      },
    },
    {
      custom_entity_check = {
        field_sources = { "cluster_nodes", "connection_is_proxied" },
        run_with_missing_fields = true,
        fn = function(entity)
          local cluster_nodes = entity.cluster_nodes
          local connection_is_proxied = entity.connection_is_proxied

          if is_present(cluster_nodes) and connection_is_proxied == true then
            return nil, "'connection_is_proxied' can not be 'true' when 'cluster_nodes' is set."
          end

          return true
        end,
      },
    },
    {
      custom_entity_check = {
        field_sources = { "sentinel_role", "connection_is_proxied" },
        run_with_missing_fields = true,
        fn = function(entity)
          local sentinel_role = entity.sentinel_role
          local connection_is_proxied = entity.connection_is_proxied

          if is_present(sentinel_role) and connection_is_proxied == true then
            return nil, "'connection_is_proxied' can not be 'true' when 'sentinel_role' is set."
          end

          return true
        end,
      },
    },
  },
  shorthand_fields = {
    {
      timeout = {
        type = "integer",
        deprecation = {
          message = "redis schema field `timeout` is deprecated, use `connect_timeout`, `send_timeout` and `read_timeout`",
          removal_in_version = "4.0",
          replaced_with = {
            { path = { "connect_timeout" } },
            { path = { "send_timeout" } },
            { path = { "read_timeout" } },
          }
        },
        func = function(value)
          if is_present(value) then
            return { connect_timeout = value, send_timeout = value, read_timeout = value }
          end
        end,
      }
    },
    {
      sentinel_addresses = {
        type = "array",
        elements = { type = "string" },
        len_min = 1,
        custom_validator =  validate_addresses,
        deprecation = {
          message = "sentinel_addresses is deprecated, please use sentinel_nodes instead",
          removal_in_version = "4.0",
          replaced_with = {
            { path = { "sentinel_nodes" },
              reverse_mapping_function = function(data)
                if not data.sentinel_nodes or data.sentinel_nodes == ngx.null then
                  return data.sentinel_nodes
                end

                return map(redis_config_utils.merge_host_port, data.sentinel_nodes)
              end
            }
          }
        },
        func = function(value)
          if not value or value == ngx.null then
            return { sentinel_nodes = value }
          end

          return { sentinel_nodes = map(redis_config_utils.split_host_port, value) }
        end,
      },
    },
    {
      cluster_addresses = {
        type = "array",
        elements = { type = "string" },
        len_min = 1,
        custom_validator =  validate_addresses,
        deprecation = {
          message = "cluster_addresses is deprecated, please use cluster_nodes instead",
          removal_in_version = "4.0",
          replaced_with = {
            { path = { "cluster_nodes" },
              reverse_mapping_function = function(data)
                if not data.cluster_nodes or data.cluster_nodes == ngx.null then
                  return data.cluster_nodes
                end

                return map(redis_config_utils.merge_ip_port, data.cluster_nodes)
              end
            }
          }
        },
        func = function(value)
          if not value or value == ngx.null then
            return { cluster_nodes = value }
          end

          return { cluster_nodes = map(redis_config_utils.split_ip_port, value) }
        end,
      },
    },
  },
}
