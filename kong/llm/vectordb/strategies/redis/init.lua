-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe"
local deep_copy = require("kong.tools.table").deep_copy
local redis_ee = require("kong.enterprise_edition.tools.redis.v2")
local utils = require("kong.llm.vectordb.strategies.redis.utils")


local DEFAULT_KEEPALIVE_TIMEOUT = 55 * 1000
local DEFAULT_KEEPALIVE_CONS = 1000

local redis_metrics_mapping = {
  euclidean = "L2",
  cosine = "COSINE",
}

local function redis_op(conf, op, key, args)
  local red, err = redis_ee.connection(conf)
  if not red then
    return nil, err
  end

  -- not return values
  red:init_pipeline()

  if conf.suffix then
    key = key .. ":" .. conf.suffix
  end

  red[op](red, key, unpack(args or {}))

  if args and args.ttl then
    red["expire"](red, key, args.ttl)
  end

  local results, err = red:commit_pipeline()
  if err then
    return nil, "failed to commit pipeline: " .. err
  end

  -- redis cluster library handles keepalive itself
  if not redis_ee.is_redis_cluster(conf) then
    red:set_keepalive(DEFAULT_KEEPALIVE_TIMEOUT, DEFAULT_KEEPALIVE_CONS)
  end

  local res = results[1]
  -- on error it returns false, err, otherwise it's the returned data
  if type(res) == "table" and #res == 2 and op ~= "KEYS" then
    return res[1], res[2]
  end

  return res
end

local function full_index_name(namespace)
  return "idx:vss_" .. namespace
end


local function database_setup(namespace, redis_config, connector_config)
  local red, err = redis_ee.connection(redis_config)
  if not red then
    return nil, err
  end

  local key = full_index_name(namespace)
  local metric = redis_metrics_mapping[connector_config.distance_metric]
  assert(metric, "unsupport metric " .. connector_config.distance_metric)

  local found, _ = redis_op(redis_config, "FT.INFO", key)
  if found then
    local def = found[5] == "index_definition" and found[6]
    local attrs = found[7] == "attributes" and found[8] and found[8][1]
    if not def or not attrs then
      kong.log.warn("[redis] does not found expected keywords in returned definition")
    -- "key_type", "JSON", "prefixes", { "whatever:" }, "default_score", "1" 
    elseif def[2] == "JSON" and def[6] == "1" and
      attrs[#attrs] == metric and attrs[#attrs - 2] == connector_config.dimensions then

      return true
    end
    kong.log.info("[redis] found existing index mismatch current config, recreating")

    local _, err = redis_op(redis_config, "FT.DROPINDEX", key)
    if err then
      kong.log.warn("[redis] error occured while dropping index: ", err)
    end
  end

  kong.log.debug("[redis] creating index")
  local _, err = redis_op(redis_config, "FT.CREATE", key, {
    "ON", "JSON",
    "PREFIX", "1", namespace .. ":", "SCORE", "1.0",
    "SCHEMA", "$.vector", "AS", "vector",
    "VECTOR", "FLAT", "6", "TYPE", "FLOAT32",
    "DIM", connector_config.dimensions,
    "DISTANCE_METRIC", metric
  })

  if err then
    return false, "failed to create index: " .. (err or "unknown error")
  end

  return true, nil
end


-- Redis is an interface for a redis database.
local Redis = {}
Redis.__index = Redis


-- Constructs a new Redis
--
-- @param string namespace the namespace to isolate different scopes
-- @param table connector_config the configuration for the driver
-- @treturn table the Redis connector object
-- @treturn string error message if any
function Redis.new(namespace, connector_config)
  local redis_config = connector_config and connector_config.redis or {}
  redis_config = deep_copy(redis_config)

  assert(connector_config.distance_metric, "distance_metric is required")
  assert(connector_config.dimensions, "dimensions is required")

  local _, err = database_setup(namespace, redis_config, connector_config)
  if err then
    return nil, err
  end

  return setmetatable({
    config = redis_config,
    namespace = namespace,
    default_threshold = connector_config.threshold,
  }, Redis)
end

-- Retrieves a entry for a given vector.
--
-- @param string vector the vector to search
-- @param number threshold the proximity threshold for results
-- @param table[opt] metadata_out if passed a table the table will be fill with metadata of the search result
-- @treturn string|number|table|nil the payload, if any
-- @treturn string error message if any
function Redis:search(vector, threshold, metadata_out)
  threshold = threshold or self.default_threshold

  local res, err = redis_op(self.config, "FT.SEARCH", full_index_name(self.namespace), {
    "@vector:[VECTOR_RANGE $range $query_vector]=>{$YIELD_DISTANCE_AS: vector_score}",
    "SORTBY", "vector_score", "DIALECT", "2", "LIMIT", "0", "4", "PARAMS", "4", "query_vector",
    utils.convert_vector_to_bytes(vector),
    "range", threshold,
  })
  if err then
    return nil, err
  end

  -- Redis will return nothing when there are no keys in the prefix
  -- Redis will return a 0 when keys were found in the index prefix, but none matched
  if not res or #res == 0 or res[1] == 0 then
    return
  end

  local nested_table = res[3]
  if not nested_table then
    return nil, "unexpected search response: no value found in result set"
  end

  local json_payload = nested_table[4]
  if not json_payload then
    return nil, "unexpected search response: no JSON payload found in result set"
  end

  local decoded_payload, err = cjson.decode(json_payload)
  if err then
    return nil, err
  end

  if type(metadata_out) == "table" then
    metadata_out.score = nested_table[1] == "vector_score" and nested_table[2]
    local key = res[2]
    metadata_out.key = key

    local ttl, err = redis_op(self.config, "ttl", key)
    if err then
      kong.log.warn("error when retrieving ttl of key: ", err)
    else
      metadata_out.ttl = ttl
    end
  end

  return decoded_payload.payload
end


-- Keys retrieves all of a pattern of keys in this space.
-- 
-- @param pattern the search/filter pattern for keys
-- @treturn table the array of keys found from the given pattern
-- @treturn string error message if any
function Redis:keys(pattern)
  local res, err = redis_op(self.config, "KEYS", pattern)
  if err then
    return nil, "failed to list keys: " .. err
  end

  if err then
    return nil, "failed to decode payload: " .. err
  end

  return res
end


local payload_t = {
  payload = 0,
  vector = 0,
}

-- Insert a cache entry for a given vector and payload.
-- Generates a unique cache key is the format of <namespace>:<vector>.
--
-- @param string vector the vector to search
-- @param string|number|table payload the payload to store as value
-- @param string[opt] key_suffix the suffix used to compose key
-- @param number[opt] ttl the TTL of the key.
-- @treturn string the key id if successful
-- @treturn string error message if any
function Redis:insert(vector, payload, key_suffix, ttl)
  local key = self.namespace .. ":" .. key_suffix
  payload_t.payload = payload
  payload_t.vector = vector -- inserting the vector into the payload is required by redis

  local encoded, err = cjson.encode(payload_t)
  if err then
    return nil, "unable to json encode the payload: " .. err
  end

  local _, err = redis_op(self.config, "JSON.SET", key, {"$", encoded, ttl = ttl})

  if err then
    return nil, err
  end
  return key
end

-- Delete a cache entry for a given vector and payload.
--
-- @param key the key to be deleted
-- @treturn boolean indicating success
-- @treturn string error message if any
function Redis:delete(key)
  return redis_op(self.config, "JSON.DEL", key)
end

-- Drop an index
--
-- @param drop_records boolean whether to also drop the keys associated with the index
-- @treturn boolean indicating success
-- @treturn string error message if any
function Redis:drop_index(drop_records)
  local params = drop_records and { "DD" } or {}
  local key = full_index_name(self.namespace)

  return redis_op(self.config, "FT.DROPINDEX", key, params)
end

-- Get a cache entry for a given vector and payload.
--
-- @param key the key to be retrived
-- @param table[opt] metadata_out if passed a table the table will be fill with metadata of the search result
-- @treturn string|number|table|nil the payload, if any
-- @treturn string error message if any
function Redis:get(key, metadata_out)
  local res, err = redis_op(self.config, "JSON.GET", key, {".payload"})
  if err then
    return nil, "failed to get key: " .. err
  end

  if not res or res == cjson.null or res == ngx.null then
    return nil, nil
  end

  res, err = cjson.decode(res)
  if err then
    return nil, "failed to decode payload: " .. err
  end

  if type(metadata_out) == "table" then
    metadata_out.key = key

    local ttl, err = redis_op(self.config, "ttl", key)
    if err then
      kong.log.warn("error when retrieving ttl of key: ", err)
    else
      metadata_out.ttl = ttl
    end
  end

  return res
end

-- Set a cache entry for a given vector and payload.
--
-- @param key the key to be set
-- @param string|number|table payload the payload to store as value
-- @param number[opt] ttl the TTL of the key.
-- @treturn boolean indicating success
-- @treturn string error message if any
function Redis:set(key, payload, ttl)
  payload_t.payload = payload
  payload_t.vector = nil
  local encoded, err = cjson.encode(payload_t)
  if err then
    return nil, "unable to json encode the payload: " .. err
  end

  return redis_op(self.config, "JSON.SET", key, {"$", encoded, ttl = ttl})
end



return Redis
