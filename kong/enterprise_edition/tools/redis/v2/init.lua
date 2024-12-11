-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--- Kong helpers for Redis integration; includes EE-only
-- features, such as Sentinel compatibility.

local redis_connector    = require "kong.enterprise_edition.tools.redis.v2.clients.redis_connector"
local redis_cluster      = require "kong.enterprise_edition.tools.redis.v2.clients.redis_cluster"
local redis_ee_schema    = require "kong.enterprise_edition.tools.redis.v2.schema"
local redis_config_utils = require "kong.tools.redis.config_utils"
local reports            = require "kong.reports"


local ngx_null = ngx.null
local gen_poolname = redis_config_utils.gen_poolname


local _M = {}

_M.config_schema = redis_ee_schema


local function is_redis_cluster(redis)
  return redis.cluster_nodes and redis.cluster_nodes ~= ngx_null
end

_M.is_redis_cluster = is_redis_cluster


local function connect_to_redis(conf)
  local connect_opts = {
    ssl = conf.ssl,
    ssl_verify = conf.ssl_verify,
    server_name = conf.server_name,
    pool_size = conf.keepalive_pool_size,
    backlog = conf.keepalive_backlog,
    pool = gen_poolname(conf),
  }

  if is_redis_cluster(conf) then
    return redis_cluster.connect(conf, connect_opts)
  else
    return redis_connector.connect(conf, connect_opts)
  end
end

function _M.connection(conf)
  local red, err = connect_to_redis(conf)

  if not red or err then
    return nil, err
  end

  reports.retrieve_redis_version(red)

  return red, nil
end


return _M
