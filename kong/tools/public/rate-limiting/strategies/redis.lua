local redis           = require "resty.redis"
local redis_connector = require "resty.redis.connector"
local utils           = require "kong.tools.utils"

local ngx_log  = ngx.log
local ERR      = ngx.ERR
local ngx_time = ngx.time
local ceil     = math.ceil
local floor    = math.floor
local tonumber = tonumber
local type     = type


local function log(lvl, ...)
  ngx_log(lvl, "[rate-limiting] ", ...)
end


local _M = {}
local mt = { __index = _M }


local function window_floor(size, time)
  return floor(time / size) * size
end


local function redis_connection(conf)
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

    if conf.database ~= 0 then
      local ok, err = red:select(conf.database)
      if not ok then
        log(ERR, "failed to change Redis database: ", err)
        red:close()
        return nil
      end
    end
  end

  return red
end


function _M.new(_, opts)
  local conf = utils.deep_copy(opts)

  if opts.sentinel_master then
    -- parse sentinel addresses
    local parsed_addresses = {}
    for i = 1, #conf.sentinel_addresses do
      local address = conf.sentinel_addresses[i]
      local parts = utils.split(address, ":")

      local parsed_address = { host = parts[1], port = tonumber(parts[2]) }

      parsed_addresses[#parsed_addresses + 1] = parsed_address
    end

    conf.parsed_sentinel_addresses = parsed_addresses
  end

  return setmetatable({
    config = conf,
  }, mt)
end


function _M:push_diffs(diffs)
  if type(diffs) ~= "table" then
    error("diffs must be a table", 2)
  end

  local red = redis_connection(self.config)
  if not red then
    return
  end

  red:init_pipeline()

  for i = 1, #diffs do
    local key     = diffs[i].key
    local windows = diffs[i].windows

    for j = 1, #windows do
      local rkey = windows[j].window .. ":" .. windows[j].size .. ":" ..
                   windows[j].namespace

      red:hincrby(rkey, key, windows[j].diff)
      red:expire(rkey, 2 * windows[j].size)
    end
  end

  local results, err = red:commit_pipeline()
  if not results then
    log(ERR, "failed to push diff pipeline: ", err)
  end

  red:set_keepalive()
end


function _M:get_counters(namespace, window_sizes, time)
  local red = redis_connection(self.config)
  if not red then
    return
  end

  time = time or ngx_time()

  red:init_pipeline()

  for i = 1, #window_sizes do
    local floor = window_floor(window_sizes[i], time)
    red:hgetall(floor .. ":" .. window_sizes[i] .. ":" .. namespace)
    red:hgetall(floor -  window_sizes[i] .. ":" .. window_sizes[i] .. ":" ..
                namespace)
  end

  local res, err = red:commit_pipeline()
  if not res then
    log(ERR, "failed to retrieve keys under namespace ", namespace, ": ", err)
    return
  end

  red:set_keepalive()

  local num_hashes = #res
  local res_idx = 0
  local hash_idx
  local hash

  local function iter()
    if not hash then
      res_idx = res_idx + 1

      if res_idx > num_hashes then
        return nil
      end

      hash = res[res_idx]
      hash_idx = 0
    end

    hash_idx = hash_idx + 1

    local key = hash[hash_idx]
    local value = hash[hash_idx + 1]
    if not key then
      hash = nil
      return iter()
    end

    -- jump past the value for this key
    hash_idx = hash_idx + 1

    -- return what looks like a psql/c* row. key and count are easy :)
    -- window size and start are a little trickier. since we are iterating over
    -- 2 * #window_sizes elements, we figure these based on our current iterator
    -- idx. the window start is either the the value of window_floor() based the
    -- current window size, or `window_size` seconds less than the current floor
    return {
      window_size = window_sizes[ceil(res_idx / 2)],
      window_start = window_floor(window_sizes[ceil(res_idx / 2)], time) -
                     (((res_idx + 1) % 2) * window_sizes[ceil(res_idx / 2)]),
      key = key,
      count = tonumber(value),
    }
  end

  return iter
end


function _M:get_window(key, namespace, window_start, window_size)
  local red = redis_connection(self.config)
  if not red then
    return
  end

  local rkey = window_start .. ":" .. window_size .. ":" .. namespace

  local res, err = red:hget(rkey, key)
  if not res then
    log(ERR, "failed to retrieve ", key, ": ", err)
  end

  red:set_keepalive()

  return tonumber(res)
end


function _M:purge()
  -- noop: redis strategy uses `:expire` to purge old entries
end

return _M
