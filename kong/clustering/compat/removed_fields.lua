-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


return {
  [2003003003] = {
    file_log = {
      "custom_fields_by_lua",
    },
    http_log = {
      "custom_fields_by_lua",
    },
    loggly = {
      "custom_fields_by_lua",
    },
    prometheus = {
      "per_consumer",
    },
    syslog = {
      "custom_fields_by_lua",
    },
    tcp_log = {
      "custom_fields_by_lua",
    },
    udp_log = {
      "custom_fields_by_lua",
    },
    zipkin = {
      "tags_header",
    },
  },

  [2004001002] = {
    redis = {
      "connect_timeout",
      "keepalive_backlog",
      "keepalive_pool_size",
      "read_timeout",
      "send_timeout",
    },
    syslog = {
      "facility",
    },
  }
}
