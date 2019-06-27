--- Kong helpers for Redis integration; includes EE-only
-- features, such as Sentinel compatibility.

local redis_connector = require "resty.redis.connector"
local redis_cluster   = require "resty.rediscluster"
local typedefs        = require "kong.db.schema.typedefs"
local utils           = require "kong.tools.utils"
local redis           = require "resty.redis"
local reports         = require "kong.reports"


local log = ngx.log
local ERR = ngx.ERR


local _M = {}


local function is_redis_sentinel(redis)
  local is_sentinel = redis.sentinel_master or
                      redis.sentinel_role or
                      redis.sentinel_addresses

  return is_sentinel and true or false
end

local function is_redis_cluster(redis)
  return redis.cluster_addresses and true or false
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
    { timeout = typedefs.timeout { default = 2000 } },
    { password = { type = "string", } },
    { database = { type = "integer", default = 0 } },
    { sentinel_master = { type = "string", } },
    { sentinel_role = { type = "string", one_of = { "master", "slave", "any" }, } },
    { sentinel_addresses = { type = "array", elements = { type = "string" }, len_min = 1, custom_validator =  validate_addresses } },
    { cluster_addresses = { type = "array", elements = { type = "string" }, len_min = 1, custom_validator =  validate_addresses } },
  },

  entity_checks = {
    {
      mutually_exclusive_sets = {
        set1 = { "sentinel_master", "sentinel_role", "sentinel_addresses" },
        set2 = { "host", "port" },
      },
    },
    {
      mutually_required = { "sentinel_master", "sentinel_role", "sentinel_addresses" },
    },
    {
      mutually_required = { "host", "port" },
    },
  }
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


-- Perform any needed Redis configuration; e.g., parse Sentinel addresses
function _M.init_conf(conf)
  if is_redis_cluster(conf) then
    conf.parsed_cluster_addresses =
      parse_addresses(conf.cluster_addresses, "ip")
  elseif is_redis_sentinel(conf) then
    conf.parsed_sentinel_addresses =
      parse_addresses(conf.sentinel_addresses, "host")
  end
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

  if is_redis_cluster(conf) then
    -- creating client for redis cluster
    local err
    red, err = redis_cluster:new({
      dict_name = "kong_locks",
      name = "redis-cluster",
      serv_list = conf.parsed_cluster_addresses,
      auth = conf.password,
    })
    if err then
      log(ERR, "failed to connect to redis cluster: ", err)
      return nil
    end
  elseif conf.sentinel_master then
    -- creating client for redis sentinel
    local rc = redis_connector.new()
    rc:set_connect_timeout(conf.timeout)

    local err
    red, err = rc:connect_via_sentinel({
      master_name = conf.sentinel_master,
      role        = conf.sentinel_role,
      sentinels   = conf.parsed_sentinel_addresses,
      password    = conf.password,
      db          = conf.database,
    })
    if err then
      log(ERR, "failed to connect to redis sentinel: ", err)
      return nil
    end
  else
    -- regular redis
    red = redis:new()
    red:set_timeout(conf.redis_timeout)

    local ok, err = red:connect(conf.host, conf.port)
    if not ok then
      log(ERR, "failed to connect to Redis: ", err)
      return nil
    end

    if conf.password and conf.password ~= "" then
      local ok, err = red:auth(conf.password)
      if not ok then
        log(ERR, "failed to auth to Redis: ", err)
        red:close() -- dont try to hold this connection open if we failed
        return nil
      end
    end

    if conf.database and conf.database ~= 0 then
      local ok, err = red:select(conf.database)
      if not ok then
        log(ERR, "failed to change Redis database: ", err)
        red:close()
        return nil
      end
    end
  end

  reports.retrieve_redis_version(red)

  return red
end


function _M.flush_redis(host, port, database, password)
  local redis = require "resty.redis"
  local red = redis:new()
  red:set_timeout(2000)
  local ok, err = red:connect(host, port)
  if not ok then
    error("failed to connect to Redis: " .. err)
  end

  if password and password ~= "" then
    local ok, err = red:auth(password)
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
