local redis_connector = require "resty.redis.connector"
local utils = require "kong.tools.utils"
local reports = require "kong.reports"
local split = utils.split
local READ = "read"
local SLAVE = "slave"
local MASTER = "master"
local _M = {}

--[[references lua-resty-redis and lua-restry-redis-connector
   https://github.com/openresty/lua-resty-redis
   https://github.com/ledgetech/lua-resty-redis-connector
  ]]
-- @table opts : contains redis configurations
function _M.new(opts)
  local conf = utils.deep_copy(opts)

  local sentinels = {}

  if conf.sentinel_addresses and #conf.sentinel_addresses > 0 then
    for _, sentinel in ipairs(conf.sentinel_addresses) do
      local splited_sentinel_address = split(sentinel, ":")
      sentinels[#sentinels + 1] = {
        host = splited_sentinel_address[1],
        port = splited_sentinel_address[2]
      }
    end
  end
  conf.sentinels = sentinels
  local self = {
    conf = conf,
    connector = redis_connector.new({
      connect_timeout = conf.connect_timeout,
      read_timeout = conf.read_timeout,
      keepalive_timeout = conf.keepalive_timeout,
      keepalive_poolsize = conf.keepalive_poolsize
    })
  }
  return setmetatable(
    self,
    {
      __index = _M
    }
  )
end

-- this function creates a Redis connection with the configurations provided and sets the connection to self.red
-- @string operation defines the read/write operation
-- @return true if Redis connection is successful and returns nil, err in case of failure
function _M:connect(operation)
  local red, err =
    self.connector:connect(
    {
      master_name = self.conf.sentinel_master,
      role = operation == READ and SLAVE or MASTER,
      sentinels = self.conf.sentinels,
      password = (self.conf.password and self.conf.password ~= "") and self.conf.password or nil,
      db = self.conf.database,
      host = self.conf.host,
      port = self.conf.port
    }
  )
  if red == nil or not red then
    ngx.log(ngx.ERR, "failed to connect redis: ", err)
    return nil, err
  end
  self.red = red
  return true, nil
end

-- this function places the given Redis connection on the keepalive pool
-- @return true if Redis connection is successful placed on the keepalive pool and returns false in case of failure
function _M:close()
  local ok, err = self.connector:set_keepalive(self.red)
  if not ok then
    ngx.log(ngx.ERR, "failed to set Redis keepalive: ", err)
    return false
  end
  return true
end

-- this function ensure ttl set for every key
-- only increments value if key is already present in datastore
-- sets a new value with the given ttl, if key doesn't present in datastore
-- @returns lua function
function _M:safe_incr()
  return "local exists = redis.call('exists', ARGV[1]) if exists == 1 then return redis.call('incrby', ARGV[1], ARGV[2]) else return redis.call('set', ARGV[1], ARGV[2], 'Ex', ARGV[3]) end"
end

--- Store a new request entity in redis
-- @string key The request key
-- @int idx The idx represents the total number of keys present
-- @table keys The array of cache keys
-- @int value The value to be set for the cache keys
-- @table expirations The array of expirations periods
-- @returns true if cache set is successful and returns nil, err in case of failure
function _M:set(idx, keys, value, expirations)
  local connected, err = self:connect()
  if not connected then
    return nil, err
  end
  for i = 1, idx do
    local ok, err = self.red:eval(self:safe_incr(),0,keys[i], value , expirations[i])
    if not ok or err then
      kong.log.err("failed to set/incr in Redis: ", err)
      return nil, err
    end
  end
  self:close()
  return true
end

--- Get a cached request
-- @string key The request key
-- @return Table representing the request
function _M:get(key)
  local connected, err = self:connect(READ)
  if not connected then
    return nil, err
  end
  reports.retrieve_redis_version(self.red)
  -- retrieve object from redis
  local current_metric, err = self.red:get(key)
  if err then
    return nil, err
  end

  self:close()
  return current_metric
end

return _M
