-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local load_module_if_exists = require("kong.tools.module").load_module_if_exists


local function bound_ttl(ttl_opts, ttl)
  if not ttl then
    return ttl_opts.default_ttl
  end

  if ttl_opts.max_ttl and ttl_opts.max_ttl > 0 and ttl > ttl_opts.max_ttl then
    return ttl_opts.max_ttl
  end

  if ttl_opts.min_ttl and ttl_opts.min_ttl > 0 and ttl < ttl_opts.min_ttl then
    return ttl_opts.min_ttl
  end

  return ttl
end


local function get_ttl_opts(args)
  local ttl_default   = args.get_conf_arg("cache_ttl", 3600)
  local ttl_max       = args.get_conf_arg("cache_ttl_max")
  local ttl_min       = args.get_conf_arg("cache_ttl_min")
  local ttl_neg       = args.get_conf_arg("cache_ttl_neg")
  local ttl_resurrect = args.get_conf_arg("cache_ttl_resurrect")

  if ttl_max and ttl_max > 0 then
    if ttl_min and ttl_min > ttl_max then
      ttl_min = ttl_max
    end
  end

  local ttl_opts = {
    min_ttl = ttl_min,
    max_ttl = ttl_max,
    neg_ttl = ttl_neg,
    resurrect_ttl = ttl_resurrect,
  }

  -- reusing the function bound_ttl to set the default ttl.
  -- The second parameter is passed thus it's fine to not have a default ttl
  ttl_opts.default_ttl = bound_ttl(ttl_opts, ttl_default)

  return ttl_opts
end


local function get_strategy(args)
  local cluster_strategy, err = nil, "not designated"

  local cluster_strategy_name = args.get_conf_arg("cluster_cache_strategy", "off")

  if cluster_strategy_name == "off" then
    return cluster_strategy, err
  end

  local ok, cluster_strategy_module = load_module_if_exists("kong.plugins.openid-connect.cache.strategy." .. cluster_strategy_name)

  if not ok then
    return nil, cluster_strategy_module
  end

  local strategy_opts = args.get_conf_arg("cluster_cache_" .. cluster_strategy_name)

  if not strategy_opts then
    return nil, "no configuration found for cluster cache strategy: " .. cluster_strategy_name
  end

  strategy_opts.ttl_opts = get_ttl_opts(args)
  return cluster_strategy_module.new(strategy_opts)
end


-- this function wraps a mlcache callback to cache with cluster level cache strategy
local function callback_wrap(strategy, key, cb, ...)
  local value, err, remain_ttl = strategy:get(key)
  if err then
    ngx.log(ngx.ERR, "failed to get value from cluster cache: ", err)
  end

  if not value and cb then
    value, err, remain_ttl = cb(...)
    -- cb remain_ttl < 0 means bypassing the cache
    if value and not (remain_ttl and remain_ttl < 0) then
      local ttl_opts = strategy.ttl_opts
      local ttl = bound_ttl(ttl_opts, remain_ttl)
      local ok
      ok, err = strategy:set(key, value, ttl)
      if not ok then
        ngx.log(ngx.ERR, "failed to set value in cluster cache: ", err)
      end
    end
  end

  return value, err, remain_ttl
end


-- get_bulk callback only accept a table as parameter so the args have to be packed into a table
local function bulk_callback_wrap(args)
  --                  strategy,     key,      cb,    args
  return callback_wrap(args[1], args[2], args[3], args[4])
end


return {
  get_ttl_opts = get_ttl_opts,
  get_strategy = get_strategy,
  callback_wrap = callback_wrap,
  bulk_callback_wrap = bulk_callback_wrap,
}
