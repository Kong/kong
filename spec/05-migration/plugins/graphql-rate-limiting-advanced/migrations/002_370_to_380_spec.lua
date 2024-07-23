-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local migration_spec_generator = require "spec.helpers.redis.schema_migrations_templates.cluster_sentinel_addreses_to_nodes_370_to_380_spec_generator"

migration_spec_generator.test_plugin_migrations({
  plugin_name = "graphql-rate-limiting-advanced",
  plugin_config = {
    window_size = { 1 },
    limit = { 10 },
    sync_rate = 0.1,
    strategy = "redis",
  }
}, "3.4.x.x") -- grapql-rate-limiting-advanced has a bug prior to version 3.4 that prevents it
              --  from configuring redis_cluster: see commit: c703c34e98141e10e2b6098cb344de24cef9fec1
              --  which has not been backported to 2.8.x.x
