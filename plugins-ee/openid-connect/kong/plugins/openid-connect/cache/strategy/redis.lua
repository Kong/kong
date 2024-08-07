-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local redis  = require("kong.enterprise_edition.tools.redis.v2")
local cjson = require("cjson.safe")
local json_encode = cjson.encode
local json_decode = cjson.decode
local table_merge = require("kong.tools.table").table_merge
local redis_connect = redis.connection

local _M = {}
local _MT = { __index = _M, }


local type = type
local ipairs = ipairs
local ngx_null = ngx.null


local DEFAULT_PREFIX = "oidc_introspection:"


-- Please do not reuse the opts table as it will be returned
-- as the strategy object
-- The opts table is intentionally not copied to avoid table
-- creation as this is called for every request
function _M.new(opts)
  opts.prefix = opts.prefix or DEFAULT_PREFIX
  return setmetatable(opts, _MT)
end


function _M:connect(opts)
  local strategy_opts
  if opts then
    strategy_opts = table_merge(self, opts)
  else
    strategy_opts = self
  end

  local ret, err = redis_connect(strategy_opts)
  if not ret then
    return nil, err
  end

  ret.is_redis_cluster = redis.is_redis_cluster(strategy_opts)
  return ret
end


-- not _M:close(red) because lualint warns about unused argument
function _M.close(_, red)
  -- redis cluster library handles keepalive itself
  if not red.is_redis_cluster then
    red:set_keepalive()
  end
end


local function get_pipeline_err(res)
  -- the res would be `{false, err}` if the query fails
  if type(res) == "table" and #res == 2 and res[1] == false then
    return res[2]
  end
end


-- TODO: negative caching? Or should it be fine to introspect multiple times?
function _M:get(key, opts)
  if type(key) ~= "string" then
    return nil, "only string keys are supported"
  end

  local red, err = self:connect(opts)
  if not red then
    return nil, err
  end

  red:init_pipeline()

  key = self.prefix .. key

  red:ttl(key)
  red:get(key)

  local results
  results, err = red:commit_pipeline()

  if not results then
    self:close(red)
    return nil, err
  end

  for _, res in ipairs(results) do
    local err_result = get_pipeline_err(res)
    if err_result then
      self:close(red)
      return nil, err_result
    end
  end

  local ttl = results[1]
  local value = results[2]
  if value == ngx_null then
    value = nil

  else
    value, err = json_decode(value)
    if not value then
      self:close(red)
      return nil, err
    end
  end

  -- -1 for no ttl and -2 for key not found
  -- both cases we do not set new ttl
  if ttl < 0 then
    ttl = nil
  end

  self:close(red)

  return value, nil, ttl
end


-- reusable table for construct Redis command
local red_args = {}


function _M:set(key, value, ttl, opts)
  local red, err = self:connect(opts)
  if not red then
    return nil, err
  end

  value, err = json_encode(value)
  if not value then
    self:close(red)
    return nil, err
  end

  -- clear the table
  red_args[1], red_args[2], red_args[3] = nil, nil, nil

  if ttl then
    -- expiration arguemnts
    red_args[1], red_args[2] = "EX", ttl
  end

  if not ((opts and opts.override) or self.override) then
    -- override argument
    red_args[#red_args + 1] = "NX"
  end

  key = self.prefix .. key

  local ok
  ok, err = red:set(key, value, red_args[1], red_args[2], red_args[3])

  self:close(red)

  return ok, err
end


function _M:del(key, opts)
  local red, err = self:connect(opts)
  if not red then
    return nil, err
  end

  key = self.prefix .. key

  local ok
  ok, err = red:del(key)

  self:close(red)

  return ok, err
end


-- This is a hidden feature due to the risk and performance implications
function _M:purge(opts)
  local red, err = self:connect(opts)
  if not red then
    return nil, err
  end

  -- we are using scan to delete all keys
  -- as the consistency is not guaranteed
  -- when using KEYS command
  local cursor = 0
  repeat
    local res
    res, err = red:scan(cursor, "MATCH", self.prefix .. "*", "COUNT", 1000)
    if not res then
      self:close(red)
      return nil, err
    end

    cursor = tonumber(res[1]) or 0
    local keys = res[2]

    for _, key in ipairs(keys) do
      red:del(key)
    end
  until cursor == 0

  self:close(red)

  return true
end

return _M
