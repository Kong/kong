--- Kong helpers for Redis integration; includes EE-only
-- features, such as Sentinel compatibility.

local redis_connector = require "resty.redis.connector"
local errors          = require "kong.dao.errors"
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

_M.config_schema = {
  fields = {
    host = {
      type = "string",
    },
    port = {
      type = "number",
    },
    timeout = {
      type = "number",
    },
    password = {
      type = "string",
    },
    database = {
      type = "number",
    },
    sentinel_master = {
      type = "string",
    },
    sentinel_role = {
      type = "string",
      enum = { "master", "slave", "any" },
    },
    sentinel_addresses = {
      type = "array",
    },
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    if is_redis_sentinel(plugin_t) then
      if not plugin_t.sentinel_master then
        return false,
               errors.schema("You need to specify a Redis Sentinel master")
      end

      if not plugin_t.sentinel_role then
        return false,
               errors.schema("You need to specify a Redis Sentinel role")
      end

      if not plugin_t.sentinel_addresses then
        return false,
               errors.schema("You need to specify one or more " ..
               "Redis Sentinel addresses")

      else
        if plugin_t.host then
          return false,
                 errors.schema("When Redis Sentinel is enabled you cannot " ..
                 "set a 'redis.host'")
        end

        if plugin_t.port then
          return false,
                 errors.schema("When Redis Sentinel is enabled you cannot " ..
                 "set a 'redis.port'")
        end

        if #plugin_t.sentinel_addresses == 0 then
          return false,
                 errors.schema("You need to specify one or more " ..
                 "Redis Sentinel addresses")
        end

        for _, address in ipairs(plugin_t.sentinel_addresses) do
          local parts = utils.split(address, ":")

          if not (#parts == 2 and tonumber(parts[2])) then
            return false,
                   errors.schema("Invalid Redis Sentinel address: " .. address)
          end
        end
      end
    else
      if not plugin_t.host then
        return false, errors.schema("Redis host must be provided")
      end

      if not plugin_t.port then
        return false, errors.schema("Redis port must be provided")
      end
    end

    if not plugin_t.database then
      plugin_t.database = 0
    end

    if not plugin_t.timeout then
      plugin_t.timeout = 2000
    end
  end,
}


-- Parse addresses from a string in the "host1:port1,host2:port2" format to a
-- table in the {{host = "host1", port = port1}, {host = "host2", port = port2}}
-- format
local function parse_sentinel_addresses(addresses)
  local parsed_addresses = {}

  for i = 1, #addresses do
    local address = addresses[i]
    local parts = utils.split(address, ":")

    local parsed_address = { host = parts[1], port = tonumber(parts[2]) }
    parsed_addresses[#parsed_addresses + 1] = parsed_address
  end

  return parsed_addresses
end


-- Perform any needed Redis configuration; e.g., parse Sentinel addresses
function _M.init_conf(conf)
  if is_redis_sentinel(conf) then
    conf.parsed_sentinel_addresses =
      parse_sentinel_addresses(conf.sentinel_addresses)
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

  if conf.sentinel_master then
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
    -- regular redis, no sentinel

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
