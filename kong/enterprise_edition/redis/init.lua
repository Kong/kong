-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Kong helpers for Redis integration; includes EE-only
-- features, such as Sentinel compatibility.

local redis_connector    = require "resty.redis.connector"
local redis_cluster      = require "resty.rediscluster"
local typedefs           = require "kong.db.schema.typedefs"
local utils              = require "kong.tools.utils"
local reports            = require "kong.reports"
local map                = require "pl.tablex".map
local redis_config_utils = require "kong.enterprise_edition.redis.config_utils"

local string_format   = string.format
local table_concat    = table.concat

local ngx_null = ngx.null

local DEFAULT_TIMEOUT = 2000
local MAX_INT = math.pow(2, 31) - 2

local _M = {}

local function is_present(x)
  return x and ngx_null ~= x
end


local function is_redis_cluster(redis)
  return is_present(redis.cluster_nodes)
end

_M.is_redis_cluster = is_redis_cluster

local function validate_addresses(addresses)
  for _, address in ipairs(addresses) do
    local parts = utils.split(address, ":")

    if not (#parts == 2 and tonumber(parts[2])) then
      return false, "Invalid Redis host address: " .. address
    end
  end

  return true
end


_M.config_schema = {
  type = "record",

  fields = {
    { host = typedefs.host },
    { port = typedefs.port },
    { connect_timeout = typedefs.timeout { default = DEFAULT_TIMEOUT } },
    { send_timeout = typedefs.timeout { default = DEFAULT_TIMEOUT } },
    { read_timeout = typedefs.timeout { default = DEFAULT_TIMEOUT } },
    { username = { description = "Username to use for Redis connections. If undefined, ACL authentication won't be performed. This requires Redis v6.0.0+. To be compatible with Redis v5.x.y, you can set it to `default`.", type = "string",
        referenceable = true
      } },
    { password = { description = "Password to use for Redis connections. If undefined, no AUTH commands are sent to Redis.", type = "string",
        encrypted = true,
        referenceable = true
      } },
    { sentinel_username = { description = "Sentinel username to authenticate with a Redis Sentinel instance. If undefined, ACL authentication won't be performed. This requires Redis v6.2.0+.", type = "string",
        referenceable = true
      } },
    { sentinel_password = { description = "Sentinel password to authenticate with a Redis Sentinel instance. If undefined, no AUTH commands are sent to Redis Sentinels.", type = "string",
        encrypted = true,
        referenceable = true
      } },
    { database = { description = "Database to use for the Redis connection when using the `redis` strategy", type = "integer",
        default = 0
      } },
    { keepalive_pool_size = { description = "The size limit for every cosocket connection pool associated with every remote server, per worker process. If neither `keepalive_pool_size` nor `keepalive_backlog` is specified, no pool is created. If `keepalive_pool_size` isn't specified but `keepalive_backlog` is specified, then the pool uses the default value. Try to increase (e.g. 512) this value if latency is high or throughput is low.", type = "integer",
        default = 256,
        between = { 1, MAX_INT }
      } },
    { keepalive_backlog = { description = "Limits the total number of opened connections for a pool. If the connection pool is full, connection queues above the limit go into the backlog queue. If the backlog queue is full, subsequent connect operations fail and return `nil`. Queued operations (subject to set timeouts) resume once the number of connections in the pool is less than `keepalive_pool_size`. If latency is high or throughput is low, try increasing this value. Empirically, this value is larger than `keepalive_pool_size`.",
        type = "integer",
        between = { 0, MAX_INT }
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
        default = false
      } },
    { ssl_verify = { description = "If set to true, verifies the validity of the server SSL certificate. If setting this parameter, also configure `lua_ssl_trusted_certificate` in `kong.conf` to specify the CA (or server) certificate used by your Redis server. You may also need to configure `lua_ssl_verify_depth` accordingly.",
        type = "boolean",
        required = false,
        default = false
      } },
    { server_name = typedefs.sni { required = false } },
    { cluster_max_redirections = { description = "Maximum retry attempts for redirection.",
        required = false,
        default = 5,
        type = "integer",
      } },
  },

  entity_checks = {
    {
      mutually_exclusive_sets = {
        set1 = { "sentinel_master", "sentinel_role", "sentinel_nodes" },
        set2 = { "host", "port" },
      },
    },
    {
      mutually_exclusive_sets = {
        set1 = { "sentinel_master", "sentinel_role", "sentinel_nodes" },
        set2 = { "cluster_nodes" },
      },
    },
    {
      mutually_exclusive_sets = {
        set1 = { "cluster_nodes" },
        set2 = { "host", "port" },
      },
    },
    {
      mutually_required = { "sentinel_master", "sentinel_role", "sentinel_nodes" },
    },
    {
      mutually_required = { "host", "port" },
    },
    {
      mutually_required = { "connect_timeout", "send_timeout", "read_timeout" },
    }
  },
  shorthand_fields = {
    {
      timeout = {
        type = "integer",
        translate_backwards = {'connect_timeout'},
        deprecation = {
          message = "redis schema field `timeout` is deprecated, use `connect_timeout`, `send_timeout` and `read_timeout`",
          removal_in_version = "4.0",
        },
        func = function(value)
          if is_present(value) then
            return { connect_timeout = value, send_timeout = value, read_timeout = value }
          end
        end
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
        },
        translate_backwards_with = function(data)
          if not data.sentinel_nodes or data.sentinel_nodes == ngx.null then
            return data.sentinel_nodes
          end

          return map(redis_config_utils.merge_host_port, data.sentinel_nodes)
        end,

        func = function(value)
          if not value or value == ngx.null then
            return { sentinel_nodes = value }
          end

          return { sentinel_nodes = map(redis_config_utils.split_host_port, value) }
        end
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
        },
        translate_backwards_with = function(data)
          if not data.cluster_nodes or data.cluster_nodes == ngx.null then
            return data.cluster_nodes
          end

          return map(redis_config_utils.merge_ip_port, data.cluster_nodes)
        end,
        func = function(value)
          if not value or value == ngx.null then
            return { cluster_nodes = value }
          end

          return { cluster_nodes = map(redis_config_utils.split_ip_port, value) }
        end
      },
    },
  }
}

-- Create a connection with Redis; expects a table with
-- required parameters. Examples:
--
-- Redis:
--   {
--     host = "127.0.0.1",
--     port = 6379,
--   }
--
-- Redis Sentinel:
--   {
--      sentinel_role = "master",
--      sentinel_master = "mymaster",
--      sentinel_addresses = "127.0.0.1:26379",
--   }
--
-- Some optional parameters are supported, e.g., Redis password,
-- database, and timeout. (See schema definition above.)
--
function _M.connection(conf)
  local red

  local connect_opts = {
    ssl = conf.ssl,
    ssl_verify = conf.ssl_verify,
    server_name = conf.server_name,
    pool_size = conf.keepalive_pool_size,
    backlog = conf.keepalive_backlog,
  }

  if is_redis_cluster(conf) then
    -- creating client for redis cluster
    local cluster_addresses = map(redis_config_utils.merge_ip_port, conf.cluster_nodes)
    local cluster_name = "redis-cluster" .. table.concat(cluster_addresses)

    local err
    red, err = redis_cluster:new({
      dict_name       = "kong_locks",
      name            = cluster_name,
      serv_list       = conf.cluster_nodes,
      username        = conf.username,
      password        = conf.password,
      connect_timeout = conf.connect_timeout,
      send_timeout    = conf.send_timeout,
      read_timeout    = conf.read_timeout,
      max_redirection = conf.cluster_max_redirections,
      connect_opts    = connect_opts,
    })
    if not red or err then
      return nil, err
    end
  else
    -- use lua-resty-redis-connector for sentinel and plain redis
    local rc = redis_connector.new({
      host               = conf.host,
      port               = conf.port,
      connect_timeout    = conf.connect_timeout,
      send_timeout       = conf.send_timeout,
      read_timeout       = conf.read_timeout,
      master_name        = conf.sentinel_master,
      role               = conf.sentinel_role,
      sentinels          = conf.sentinel_nodes,
      username           = conf.username,
      password           = conf.password,
      sentinel_username  = conf.sentinel_username,
      sentinel_password  = conf.sentinel_password,
      db                 = conf.database,
      connection_options = connect_opts,
    })

    local err, previous_errors
    -- When trying to connect on multiple hosts, the resty-redis-connector will record the errors
    -- inside a third return value, see https://github.com/ledgetech/lua-resty-redis-connector/blob
    -- /03dff6da124ec0a6ea6fa1f7fd2a0a47dc27c33d/lib/resty/redis/connector.lua#L343-L344
    -- for more details.
    -- Note that this third return value is not recorded in the official documentation
    red, err, previous_errors = rc:connect()
    if not red or err then
      if previous_errors then
        err = string_format("current errors: %s, previous errors: %s",
                                      err, table_concat(previous_errors, ", "))
      end

      return nil, err
    end
  end

  reports.retrieve_redis_version(red)

  return red, nil
end


return _M
