return {
  ["custom_plugins"] = {type = "array", default = {}},
  ["nginx_working_dir"] = {type = "string", default = "/usr/local/kong"},
  ["proxy_listen"] = {type = "string", default = "0.0.0.0:8000"},
  ["proxy_listen_ssl"] = {type = "string", default = "0.0.0.0:8443"},
  ["admin_api_listen"] = {type = "string", default = "0.0.0.0:8001"},
  ["cluster_listen"] = {type = "string", default = "0.0.0.0:7946"},
  ["cluster_listen_rpc"] = {type = "string", default = "127.0.0.1:7373"},
  ["dns_resolver"] = {type = "string", default = "dnsmasq", enum = {"server", "dnsmasq"}},
  ["dns_resolvers_available"] = {
    type = "table",
    content = {
      ["server"] = {
        type = "table",
        content = {
          ["address"] = {type = "string", default = "8.8.8.8"}
        }
      },
      ["dnsmasq"] = {
        type = "table",
        content = {
          ["port"] = {type = "number", default = 8053}
        }
      }
    }
  },
  ["cluster"] = {
    type = "table",
    content = {
      ["auto-join"] = {type = "boolean", default = true},
      ["advertise"] = {type = "string", nullable = true},
      ["encrypt"] = {type = "string", nullable = true},
      ["profile"] = {type = "string", default = "wan", enum = {"wan", "lan", "local"}},
      ["ttl_on_failure"] = {type = "number", default = 3600, min = 60}
    }
  },
  ["database"] = {type = "string", default = "cassandra", enum = {"cassandra", "postgres"}},
  ["postgres"] = {
    type = "table",
    content = {
      ["host"] = {type = "string", default = "127.0.0.1"},
      ["port"] = {type = "number", default = 5432},
      ["user"] = {type = "string", default = "kong"},
      ["database"] = {type = "string", default = "kong"},
      ["password"] = {type = "string", nullable = true}
    }
  },
  ["cassandra"] = {
    type = "table",
    content = {
      ["contact_points"] = {type = "array", default = {"127.0.0.1:9042"}},
      ["port"] = {type = "number", default = 9042},
      ["keyspace"] = {type = "string", default = "kong"},
      ["timeout"] = {type = "number", default = 5000},
      ["replication_strategy"] = {type = "string", default = "SimpleStrategy", enum = {"SimpleStrategy", "NetworkTopologyStrategy"}},
      ["replication_factor"] = {type = "number", default = 1},
      ["data_centers"] = {type = "table", default = {}},
      ["username"] = {type = "string", nullable = true},
      ["password"] = {type = "string", nullable = true},
      ["consistency"] = {type = "string", default = "ONE", enum = {"ANY", "ONE", "TWO", "THREE", "QUORUM", "ALL", "LOCAL_QUORUM",
                                                                   "EACH_QUORUM", "SERIAL", "LOCAL_SERIAL", "LOCAL_ONE"}},
      ["ssl"] = {
        type = "table",
        content = {
          ["enabled"] = {type = "boolean", default = false},
          ["verify"] = {type = "boolean", default = false},
          ["certificate_authority"] = {type = "string", nullable = true}
        }
      }
    }
  },
  ["ssl_cert_path"] = {type = "string", nullable = true},
  ["ssl_key_path"] = {type = "string", nullable = true},
  ["send_anonymous_reports"] = {type = "boolean", default = true},
  ["memory_cache_size"] = {type = "number", default = 128, min = 32},
  ["nginx"] = {type = "string", nullable = true}
}
