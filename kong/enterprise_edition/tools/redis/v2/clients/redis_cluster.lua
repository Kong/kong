-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local redis_cluster = require "resty.rediscluster"
local map = require "pl.tablex".map
local redis_config_utils = require  "kong.enterprise_edition.tools.redis.v2.config_utils"

local function connect(conf, connect_opts)
  local cluster_addresses = map(redis_config_utils.merge_ip_port, conf.cluster_nodes)

  local cluster_name = "redis-cluster" .. table.concat(cluster_addresses)

  -- creating client for redis cluster
  return redis_cluster:new({
    dict_name       = "kong_locks",
    name            = cluster_name,
    serv_list       = conf.cluster_nodes,
    username        = conf.username,
    password        = conf.password,
    connect_timeout = conf.connect_timeout,
    send_timeout    = conf.send_timeout,
    read_timeout    = conf.read_timeout,
    max_redirection = conf.cluster_max_redirections,
    connect_opts    = connect_opts,
  })
end

return {
  connect = connect
}
