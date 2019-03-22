local cjson = require "cjson.safe"
local redis = require "kong.enterprise_edition.redis"
local utils = require "kong.tools.utils"


local type         = type
local time         = ngx.time
local tonumber     = tonumber
local unpack       = unpack
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


local _M = {}


function _M.new(opts)
  local conf = utils.deep_copy(opts)

  local ok, feature_flags = utils.load_module_if_exists("kong.enterprise_edition.feature_flags")
  if ok and feature_flags then
    local namespace, err = feature_flags.get_feature_value(feature_flags.VALUES.REDIS_NAMESPACE)
    if not err then
      conf.suffix = namespace
    end
  end

  -- initialize redis configuration - e.g., parse
  -- Sentinel addresses
  redis.init_conf(conf)

  return setmetatable({
    conf = conf
  }, {
    __index = _M,
  })
end


local function exec_redis_op(conf, op, args)
  -- if args is not nil, its first element must be the hash key and it must
  -- be a string
  if args and args[1] and type(args[1]) ~= "string" then
    return nil, "key must be a string"
  end

  local red, err = redis.connection(conf)
  if not red then
    return nil, err
  end

  if conf.suffix then
    args[1] = args[1] .. ":" .. conf.suffix
  end
  red:init_pipeline()

  red[op](red, unpack(args or {}))

  -- if operation is hmset, set expiry timestamp
  if op == "hmset" and args.ttl then
    red["expire"](red, args[1], args.ttl)
  end

  local res, err = red:commit_pipeline()
  if not res then
    return nil, "failed to commit pipeline: " .. err
  end

  -- res[1] contains the result of 'op'
  res = res[1]

  -- if operation is hgetall, convert the result to a hash table
  if op == "hgetall" then
    res = red:array_to_hash(res)
  end

  red:set_keepalive()

  return res
end


function _M:store(key, req_obj, req_ttl)
  local old_headers = req_obj.headers
  local headers = cjson_encode(old_headers)
  if not headers then
    return nil, "could not encode request object"
  end

  req_obj.headers = headers
  local res, err = exec_redis_op(self.conf, "hmset", {key, req_obj, ttl = req_ttl})
  if not res then
    return nil, err
  end

  req_obj.headers = old_headers

  return res
end


function _M:fetch(key)
  local req_obj, err = exec_redis_op(self.conf, "hgetall", {key})
  if not req_obj then
    return nil, err
  end

  -- if object is an empty table
  if not next(req_obj) then
    return nil, "request object not in cache"
  end

  local headers = cjson_decode(req_obj.headers)
  if not headers then
    return nil, "could not decode request object"
  end
  req_obj.headers = headers

  if req_obj.status then
    req_obj.status = tonumber(req_obj.status)
  end

  if req_obj.body_len then
    req_obj.body_len = tonumber(req_obj.body_len)
  end

  if req_obj.timestamp then
    req_obj.timestamp = tonumber(req_obj.timestamp)
  end

  if req_obj.ttl then
    req_obj.ttl = tonumber(req_obj.ttl)
  end

  if req_obj.version then
    req_obj.version = tonumber(req_obj.version)
  end

  return req_obj
end


function _M:purge(key)
  return exec_redis_op(self.conf, "del", {key})
end


function _M:touch(key, req_ttl, timestamp)
  return exec_redis_op(self.conf, "hmset",
                       {key, "timestamp", timestamp or time(), ttl = req_ttl})
end


-- XXX does not honor free_mem
function _M:flush(free_mem)
  return exec_redis_op(self.conf, "flushdb")
end


return _M
