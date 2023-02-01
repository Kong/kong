-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Kong helpers for Redis integration; includes EE-only
-- features, such as Sentinel compatibility.

local redis_connector = require "resty.redis.connector"
local redis_cluster   = require "resty.rediscluster"
local typedefs        = require "kong.db.schema.typedefs"
local utils           = require "kong.tools.utils"
local reports         = require "kong.reports"

local log = ngx.log
local ERR = ngx.ERR
local WARN = ngx.WARN
local ngx_null = ngx.null

local DEFAULT_TIMEOUT = 2000
local MAX_INT = math.pow(2, 31) - 2

local _M = {}

local function is_present(x)
  return x and ngx_null ~= x
end


local function is_redis_sentinel(redis)
  return is_present(redis.sentinel_master) or
    is_present(redis.sentinel_role) or
    is_present(redis.sentinel_addresses)
end

local function is_redis_cluster(redis)
  return is_present(redis.cluster_addresses)
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
    { timeout = typedefs.timeout { default = DEFAULT_TIMEOUT } },
    { connect_timeout = typedefs.timeout },
    { send_timeout = typedefs.timeout },
    { read_timeout = typedefs.timeout },
    { username = { type = "string", referenceable = true } },
    { password = { type = "string", encrypted = true, referenceable = true } },
    { sentinel_username = { type = "string", referenceable = true } },
    { sentinel_password = { type = "string", encrypted = true, referenceable = true } },
    { database = { type = "integer", default = 0 } },
    { keepalive_pool_size = { type = "integer", default = 30, between = { 1, MAX_INT } } },
    { keepalive_backlog = { type = "integer", between = { 0, MAX_INT } } },
    { sentinel_master = { type = "string", } },
    { sentinel_role = { type = "string", one_of = { "master", "slave", "any" }, } },
    { sentinel_addresses = { type = "array", elements = { type = "string" }, len_min = 1, custom_validator =  validate_addresses } },
    { cluster_addresses = { type = "array", elements = { type = "string" }, len_min = 1, custom_validator =  validate_addresses } },
    { ssl = { type = "boolean", required = false, default = false } },
    { ssl_verify = { type = "boolean", required = false, default = false } },
    { server_name = typedefs.sni { required = false } },
  },

  entity_checks = {
    {
      mutually_exclusive_sets = {
        set1 = { "sentinel_master", "sentinel_role", "sentinel_addresses" },
        set2 = { "host", "port" },
      },
    },
    {
      mutually_exclusive_sets = {
        set1 = { "sentinel_master", "sentinel_role", "sentinel_addresses" },
        set2 = { "cluster_addresses" },
      },
    },
    {
      mutually_exclusive_sets = {
        set1 = { "cluster_addresses" },
        set2 = { "host", "port" },
      },
    },
    {
      mutually_required = { "sentinel_master", "sentinel_role", "sentinel_addresses" },
    },
    {
      mutually_required = { "host", "port" },
    },
    {
      mutually_required = { "connect_timeout", "send_timeout", "read_timeout" },
    }
  },
}


-- Parse addresses from a string in the "ip1:port1,ip2:port2" format to a
-- table in the {{[ip_field_name] = "ip1", port = port1}, {[ip_field_name] = "ip2", port = port2}}
-- format
local function parse_addresses(addresses, ip_field_name)
  local parsed_addresses = {}

  for i = 1, #addresses do
    local address = addresses[i]
    local parts = utils.split(address, ":")

    local parsed_address = { [ip_field_name] = parts[1], port = tonumber(parts[2]) }
    parsed_addresses[#parsed_addresses + 1] = parsed_address
  end

  return parsed_addresses
end


-- Ensures connect, send and read timeouts are individually set if only
-- the (deprecated) `timeout` field is given.
local function configure_timeouts(conf)
  local timeout = conf.timeout

  if timeout ~= DEFAULT_TIMEOUT then
    -- TODO: Move to a global util once available
    local deprecation = {
      msg = "redis schema field `timeout` is deprecated, " ..
            "use `connect_timeout`, `send_timeout` and `read_timeout`",
      deprecated_after = "2.5.0.0",
      version_removed  = "3.0.0.0",
    }

    log(
      WARN, deprecation.msg,
      " (deprecated after ", deprecation.deprecated_after,
      ", scheduled for removal in ", deprecation.version_removed, ")"
    )
  end

  conf.connect_timeout =
    conf.connect_timeout ~= ngx_null and conf.connect_timeout or timeout

  conf.send_timeout =
    conf.send_timeout ~= ngx_null and conf.send_timeout or timeout

  conf.read_timeout =
    conf.read_timeout ~= ngx_null and conf.read_timeout or timeout
end


-- Perform any needed Redis configuration; e.g., parse Sentinel addresses
function _M.init_conf(conf)
  if is_redis_cluster(conf) then
    table.sort(conf.cluster_addresses)
    conf.parsed_cluster_addresses =
      parse_addresses(conf.cluster_addresses, "ip")
  elseif is_redis_sentinel(conf) then
    conf.parsed_sentinel_addresses =
      parse_addresses(conf.sentinel_addresses, "host")
  end

  configure_timeouts(conf)
end


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
    local err
    red, err = redis_cluster:new({
      dict_name       = "kong_locks",
      name            = "redis-cluster" .. table.concat(conf.cluster_addresses),
      serv_list       = conf.parsed_cluster_addresses,
      username        = conf.username,
      password        = conf.password,
      connect_timeout = conf.connect_timeout,
      send_timeout    = conf.send_timeout,
      read_timeout    = conf.read_timeout,
      connect_opts    = connect_opts,
    })
    if not red or err then
      log(ERR, "failed to connect to redis cluster: ", err)
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
      sentinels          = conf.parsed_sentinel_addresses,
      username           = conf.username,
      password           = conf.password,
      sentinel_username  = conf.sentinel_username,
      sentinel_password  = conf.sentinel_password,
      db                 = conf.database,
      connection_options = connect_opts,
    })

    local err
    red, err = rc:connect()
    if not red or err then
      log(ERR, "failed to connect to redis: ", err)
      return nil, err
    end
  end

  reports.retrieve_redis_version(red)

  return red, nil
end


function _M.flush_redis(host, port, database, username, password)
  local redis = require "resty.redis"
  local red = redis:new()
  red:set_timeout(2000)
  local ok, err = red:connect(host, port)
  if not ok then
    error("failed to connect to Redis: " .. err)
  end

  if password and password ~= "" then
    local ok, err
    if username and username ~= "" then
      ok, err = red:auth(username, password)
    else
      ok, err = red:auth(password)
    end
    if not ok then
      error("failed to connect to Redis: " .. err)
    end
  end

  local ok, err = red:select(database)
  if not ok then
    error("failed to change Redis database: " .. err)
  end

  red:flushall()
  red:close()
end


return _M
