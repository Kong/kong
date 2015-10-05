return {
  ["plugins_available"] = {type = "array",
    default = {"ssl", "jwt", "acl", "cors", "oauth2", "tcp-log", "udp-log", "file-log",
               "http-log", "key-auth", "hmac-auth", "basic-auth", "ip-restriction",
               "mashape-analytics", "request-transformer", "response-transformer",
               "request-size-limiting", "rate-limiting", "response-ratelimiting"}
  },
  ["nginx_working_dir"] = {type = "string", default = "/usr/local/kong"},
  ["proxy_port"] = {type = "number", default = 8000},
  ["proxy_ssl_port"] = {type = "number", default = 8443},
  ["admin_api_port"] = {type = "number", default = 8001},
  ["dnsmasq_port"] = {type = "number", default = 8053},
  ["database"] = {type = "string", default = "cassandra"},
  ["databases_available"] = {
    type = "table",
    content = {
      ["cassandra"] = {
        type = "table",
        content = {
          ["contact_points"] = {type = "array", default = {"localhost:9042"}},
          ["timeout"] = {type = "number", default = 1000},
          ["keyspace"] = {type = "string", default = "kong"},
          ["keepalive"] = {type = "number", default = 60000},
          ["replication_strategy"] = {type = "string", default = "SimpleStrategy"},
          ["replication_factor"] = {type = "number", default = 1},
          ["data_centers"] = {type = "table", default = {}},
          ["ssl"] = {type = "boolean", default = false},
          ["ssl_verify"] = {type = "boolean", default = false},
          ["ssl_certificate"] = {type = "string", nullable = true},
          ["user"] = {type = "string", nullable = true},
          ["password"] = {type = "string", nullable = true}
        }
      }
    }
  },
  ["database_cache_expiration"] = {type = "number", default = 5},
  ["ssl_cert_path"] = {type = "string", nullable = true},
  ["ssl_key_path"] = {type = "string", nullable = true},
  ["send_anonymous_reports"] = {type = "boolean", default = false},
  ["memory_cache_size"] = {type = "number", default = 128, min = 32},
  ["nginx"] = {type = "string", nullable = true}
}
