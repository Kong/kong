
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
  },

  -- Any dataplane older than 2.6.0
  [2005999999] = {
    aws_lambda = {
      "base64_encode_body",
    },
    grpc_web = {
      "allow_origin_header",
    },
    request_termination = {
      "echo",
      "trigger",
    },
  },

  -- Any dataplane older than 2.7.0
  [2006999999] = {
    rate_limiting = {
      "redis_ssl",
      "redis_ssl_verify",
      "redis_server_name",
    },
  },
}
