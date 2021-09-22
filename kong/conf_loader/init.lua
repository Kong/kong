local kong_default_conf = require "kong.templates.kong_defaults"
local openssl_pkey = require "resty.openssl.pkey"
local pl_stringio = require "pl.stringio"
local pl_stringx = require "pl.stringx"
local constants = require "kong.constants"
local listeners = require "kong.conf_loader.listeners"
local pl_pretty = require "pl.pretty"
local pl_config = require "pl.config"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local tablex = require "pl.tablex"
local utils = require "kong.tools.utils"
local log = require "kong.cmd.utils.log"
local env = require "kong.cmd.utils.env"
local ffi = require "ffi"


local fmt = string.format
local concat = table.concat
local C = ffi.C

ffi.cdef([[
  struct group *getgrnam(const char *name);
  struct passwd *getpwnam(const char *name);
]])


-- Version 5: https://wiki.mozilla.org/Security/Server_Side_TLS
local cipher_suites = {
                   modern = {
                protocols = "TLSv1.3",
                  ciphers = nil,   -- all TLSv1.3 ciphers are considered safe
    prefer_server_ciphers = "off", -- as all are safe, let client choose
  },
             intermediate = {
                protocols = "TLSv1.2 TLSv1.3",
                  ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:"
                         .. "ECDHE-RSA-AES128-GCM-SHA256:"
                         .. "ECDHE-ECDSA-AES256-GCM-SHA384:"
                         .. "ECDHE-RSA-AES256-GCM-SHA384:"
                         .. "ECDHE-ECDSA-CHACHA20-POLY1305:"
                         .. "ECDHE-RSA-CHACHA20-POLY1305:"
                         .. "DHE-RSA-AES128-GCM-SHA256:"
                         .. "DHE-RSA-AES256-GCM-SHA384",
                 dhparams = "ffdhe2048",
    prefer_server_ciphers = "off",
  },
                      old = {
                protocols = "TLSv1 TLSv1.1 TLSv1.2 TLSv1.3",
                  ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:"
                         .. "ECDHE-RSA-AES128-GCM-SHA256:"
                         .. "ECDHE-ECDSA-AES256-GCM-SHA384:"
                         .. "ECDHE-RSA-AES256-GCM-SHA384:"
                         .. "ECDHE-ECDSA-CHACHA20-POLY1305:"
                         .. "ECDHE-RSA-CHACHA20-POLY1305:"
                         .. "DHE-RSA-AES128-GCM-SHA256:"
                         .. "DHE-RSA-AES256-GCM-SHA384:"
                         .. "DHE-RSA-CHACHA20-POLY1305:"
                         .. "ECDHE-ECDSA-AES128-SHA256:"
                         .. "ECDHE-RSA-AES128-SHA256:"
                         .. "ECDHE-ECDSA-AES128-SHA:"
                         .. "ECDHE-RSA-AES128-SHA:"
                         .. "ECDHE-ECDSA-AES256-SHA384:"
                         .. "ECDHE-RSA-AES256-SHA384:"
                         .. "ECDHE-ECDSA-AES256-SHA:"
                         .. "ECDHE-RSA-AES256-SHA:"
                         .. "DHE-RSA-AES128-SHA256:"
                         .. "DHE-RSA-AES256-SHA256:"
                         .. "AES128-GCM-SHA256:"
                         .. "AES256-GCM-SHA384:"
                         .. "AES128-SHA256:"
                         .. "AES256-SHA256:"
                         .. "AES128-SHA:"
                         .. "AES256-SHA:"
                         .. "DES-CBC3-SHA",
    prefer_server_ciphers = "on",
  }
}


local DEFAULT_PATHS = {
  "/etc/kong/kong.conf",
  "/etc/kong.conf",
}


local HEADERS = constants.HEADERS
local HEADER_KEY_TO_NAME = {
  ["server_tokens"] = "server_tokens",
  ["latency_tokens"] = "latency_tokens",
  [string.lower(HEADERS.VIA)] = HEADERS.VIA,
  [string.lower(HEADERS.SERVER)] = HEADERS.SERVER,
  [string.lower(HEADERS.PROXY_LATENCY)] = HEADERS.PROXY_LATENCY,
  [string.lower(HEADERS.RESPONSE_LATENCY)] = HEADERS.RESPONSE_LATENCY,
  [string.lower(HEADERS.ADMIN_LATENCY)] = HEADERS.ADMIN_LATENCY,
  [string.lower(HEADERS.UPSTREAM_LATENCY)] = HEADERS.UPSTREAM_LATENCY,
  [string.lower(HEADERS.UPSTREAM_STATUS)] = HEADERS.UPSTREAM_STATUS,
}


local EMPTY = {}


-- NOTE! Prefixes should always follow `nginx_[a-z]+_`.
local DYNAMIC_KEY_NAMESPACES = {
  {
    injected_conf_name = "nginx_main_directives",
    prefix = "nginx_main_",
    ignore = EMPTY,
  },
  {
    injected_conf_name = "nginx_events_directives",
    prefix = "nginx_events_",
    ignore = EMPTY,
  },
  {
    injected_conf_name = "nginx_http_directives",
    prefix = "nginx_http_",
    ignore = {
      upstream_keepalive          = true,
      upstream_keepalive_timeout  = true,
      upstream_keepalive_requests = true,
    },
  },
  {
    injected_conf_name = "nginx_upstream_directives",
    prefix = "nginx_upstream_",
    ignore = EMPTY,
  },
  {
    injected_conf_name = "nginx_proxy_directives",
    prefix = "nginx_proxy_",
    ignore = EMPTY,
  },
  {
    injected_conf_name = "nginx_status_directives",
    prefix = "nginx_status_",
    ignore = EMPTY,
  },
  {
    injected_conf_name = "nginx_admin_directives",
    prefix = "nginx_admin_",
    ignore = EMPTY,
  },
  {
    injected_conf_name = "nginx_stream_directives",
    prefix = "nginx_stream_",
    ignore = EMPTY,
  },
  {
    injected_conf_name = "nginx_supstream_directives",
    prefix = "nginx_supstream_",
    ignore = EMPTY,
  },
  {
    injected_conf_name = "nginx_sproxy_directives",
    prefix = "nginx_sproxy_",
    ignore = EMPTY,
  },
  {
    prefix = "pluginserver_",
    ignore = EMPTY,
  },
}


local DEPRECATED_DYNAMIC_KEY_NAMESPACES = {
  {
    injected_conf_name = "nginx_upstream_directives",
    previous_conf_name = "nginx_http_upstream_directives",
  },
  {
    injected_conf_name = "nginx_status_directives",
    previous_conf_name = "nginx_http_status_directives",
  },
}


local PREFIX_PATHS = {
  nginx_pid = {"pids", "nginx.pid"},
  nginx_err_logs = {"logs", "error.log"},
  nginx_acc_logs = {"logs", "access.log"},
  admin_acc_logs = {"logs", "admin_access.log"},
  nginx_conf = {"nginx.conf"},
  nginx_kong_conf = {"nginx-kong.conf"},
  nginx_kong_stream_conf = {"nginx-kong-stream.conf"},

  kong_env = {".kong_env"},

  ssl_cert_csr_default = {"ssl", "kong-default.csr"},
  ssl_cert_default = {"ssl", "kong-default.crt"},
  ssl_cert_key_default = {"ssl", "kong-default.key"},
  ssl_cert_default_ecdsa = {"ssl", "kong-default-ecdsa.crt"},
  ssl_cert_key_default_ecdsa = {"ssl", "kong-default-ecdsa.key"},

  client_ssl_cert_default = {"ssl", "kong-default.crt"},
  client_ssl_cert_key_default = {"ssl", "kong-default.key"},

  admin_ssl_cert_default = {"ssl", "admin-kong-default.crt"},
  admin_ssl_cert_key_default = {"ssl", "admin-kong-default.key"},
  admin_ssl_cert_default_ecdsa = {"ssl", "admin-kong-default-ecdsa.crt"},
  admin_ssl_cert_key_default_ecdsa = {"ssl", "admin-kong-default-ecdsa.key"},

  status_ssl_cert_default = {"ssl", "status-kong-default.crt"},
  status_ssl_cert_key_default = {"ssl", "status-kong-default.key"},
  status_ssl_cert_default_ecdsa = {"ssl", "status-kong-default-ecdsa.crt"},
  status_ssl_cert_key_default_ecdsa = {"ssl", "status-kong-default-ecdsa.key"},
}


local function is_predefined_dhgroup(group)
  if type(group) ~= "string" then
    return false
  end

  return not not openssl_pkey.paramgen({
    type = "DH",
    group = group,
  })
end


local function upstream_keepalive_deprecated_properties(conf)
  -- nginx_http_upstream_keepalive -> nginx_upstream_keepalive
  if conf.nginx_upstream_keepalive == nil then
    if conf.nginx_http_upstream_keepalive ~= nil then
      conf.nginx_upstream_keepalive = conf.nginx_http_upstream_keepalive
    end
  end

  -- upstream_keepalive -> nginx_upstream_keepalive + nginx_http_upstream_keepalive
  if conf.nginx_upstream_keepalive == nil then
    if conf.upstream_keepalive ~= nil then
      if conf.upstream_keepalive == 0 then
        conf.nginx_upstream_keepalive = "NONE"
        conf.nginx_http_upstream_keepalive = "NONE"

      else
        conf.nginx_upstream_keepalive = tostring(conf.upstream_keepalive)
        conf.nginx_http_upstream_keepalive = tostring(conf.upstream_keepalive)
      end
    end
  end

  -- nginx_upstream_keepalive -> upstream_keepalive_pool_size
  if conf.upstream_keepalive_pool_size == nil then
    if conf.nginx_upstream_keepalive ~= nil then
      if conf.nginx_upstream_keepalive == "NONE" then
        conf.upstream_keepalive_pool_size = 0

      else
        conf.upstream_keepalive_pool_size = tonumber(conf.nginx_upstream_keepalive)
      end
    end
  end

  -- nginx_http_upstream_keepalive_requests -> nginx_upstream_keepalive_requests
  if conf.nginx_upstream_keepalive_requests == nil then
    conf.nginx_upstream_keepalive_requests = conf.nginx_http_upstream_keepalive_requests
  end

  -- nginx_upstream_keepalive_requests -> upstream_keepalive_max_requests
  if conf.upstream_keepalive_max_requests == nil
     and conf.nginx_upstream_keepalive_requests ~= nil
  then
    conf.upstream_keepalive_max_requests = tonumber(conf.nginx_upstream_keepalive_requests)
  end

  -- nginx_http_upstream_keepalive_timeout -> nginx_upstream_keepalive_timeout
  if conf.nginx_upstream_keepalive_timeout == nil then
    conf.nginx_upstream_keepalive_timeout = conf.nginx_http_upstream_keepalive_timeout
  end
  --
  -- nginx_upstream_keepalive_timeout -> upstream_keepalive_idle_timeout
  if conf.upstream_keepalive_idle_timeout == nil
     and conf.nginx_upstream_keepalive_timeout ~= nil
  then
    conf.upstream_keepalive_idle_timeout =
      utils.nginx_conf_time_to_seconds(conf.nginx_upstream_keepalive_timeout)
  end
end


-- By default, all properties in the configuration are considered to
-- be strings/numbers, but if we want to forcefully infer their type, specify it
-- in this table.
-- Also holds "enums" which are lists of valid configuration values for some
-- settings.
-- See `typ_checks` for the validation function of each type.
--
-- Types:
-- `boolean`: can be "on"/"off"/"true"/"false", will be inferred to a boolean
-- `ngx_boolean`: can be "on"/"off", will be inferred to a string
-- `array`: a comma-separated list
local CONF_INFERENCES = {
  -- forced string inferences (or else are retrieved as numbers)
  port_maps = { typ = "array" },
  proxy_listen = { typ = "array" },
  admin_listen = { typ = "array" },
  status_listen = { typ = "array" },
  stream_listen = { typ = "array" },
  cluster_listen = { typ = "array" },
  ssl_cert = { typ = "array" },
  ssl_cert_key = { typ = "array" },
  admin_ssl_cert = { typ = "array" },
  admin_ssl_cert_key = { typ = "array" },
  status_ssl_cert = { typ = "array" },
  status_ssl_cert_key = { typ = "array" },
  db_update_frequency = {  typ = "number"  },
  db_update_propagation = {  typ = "number"  },
  db_cache_ttl = {  typ = "number"  },
  db_cache_neg_ttl = {  typ = "number"  },
  db_resurrect_ttl = {  typ = "number"  },
  db_cache_warmup_entities = { typ = "array" },
  nginx_user = {
    typ = "string",
    alias = {
      replacement = "nginx_main_user",
    }
  },
  nginx_daemon = {
    typ = "ngx_boolean",
    alias = {
      replacement = "nginx_main_daemon",
    }
  },
  nginx_worker_processes = {
    typ = "string",
    alias = {
      replacement = "nginx_main_worker_processes",
    },
  },

  -- TODO: remove since deprecated in 1.3
  upstream_keepalive = {
    typ = "number",
    deprecated = {
      replacement = "upstream_keepalive_pool_size",
      alias = upstream_keepalive_deprecated_properties,
    }
  },

  -- TODO: remove since deprecated in 2.0
  nginx_http_upstream_keepalive = {
    typ = "string",
    deprecated = {
      replacement = "upstream_keepalive_pool_size",
      alias = upstream_keepalive_deprecated_properties,
    }
  },
  nginx_http_upstream_keepalive_requests = {
    typ = "string",
    deprecated = {
      replacement = "upstream_keepalive_max_requests",
      alias = upstream_keepalive_deprecated_properties,
    }
  },
  nginx_http_upstream_keepalive_timeout = {
    typ = "string",
    deprecated = {
      replacement = "upstream_keepalive_idle_timeout",
      alias = upstream_keepalive_deprecated_properties,
    }
  },

  -- TODO: remove since deprecated in 2.1
  nginx_upstream_keepalive = {
    typ = "string",
    deprecated = {
      replacement = "upstream_keepalive_pool_size",
      alias = upstream_keepalive_deprecated_properties,
    }
  },
  nginx_upstream_keepalive_requests = {
    typ = "string",
    deprecated = {
      replacement = "upstream_keepalive_max_requests",
      alias = upstream_keepalive_deprecated_properties,
    }
  },
  nginx_upstream_keepalive_timeout = {
    typ = "string",
    deprecated = {
      replacement = "upstream_keepalive_idle_timeout",
      alias = upstream_keepalive_deprecated_properties,
    }
  },

  upstream_keepalive_pool_size = { typ = "number" },
  upstream_keepalive_max_requests = { typ = "number" },
  upstream_keepalive_idle_timeout = { typ = "number" },

  headers = { typ = "array" },
  trusted_ips = { typ = "array" },
  real_ip_header = {
    typ = "string",
    alias = {
      replacement = "nginx_proxy_real_ip_header",
    }
  },
  real_ip_recursive = {
    typ = "ngx_boolean",
    alias = {
      replacement = "nginx_proxy_real_ip_recursive",
    }
  },
  client_max_body_size = {
    typ = "string",
    deprecated = {
      replacement = "nginx_http_client_max_body_size",
      alias = function(conf)
        if conf.nginx_http_client_max_body_size == nil then
          conf.nginx_http_client_max_body_size = conf.client_max_body_size
        end
      end,
    }
  },
  client_body_buffer_size = {
    typ = "string",
    deprecated = {
      replacement = "nginx_http_client_body_buffer_size",
      alias = function(conf)
        if conf.nginx_http_client_body_buffer_size == nil then
          conf.nginx_http_client_body_buffer_size = conf.client_body_buffer_size
        end
      end,
    }
  },
  error_default_type = { enum = {
                           "application/json",
                           "application/xml",
                           "text/html",
                           "text/plain",
                         }
                       },

  database = { enum = { "postgres", "cassandra", "off" }  },
  pg_port = { typ = "number" },
  pg_timeout = { typ = "number" },
  pg_password = { typ = "string" },
  pg_ssl = { typ = "boolean" },
  pg_ssl_verify = { typ = "boolean" },
  pg_max_concurrent_queries = { typ = "number" },
  pg_semaphore_timeout = { typ = "number" },

  pg_ro_port = { typ = "number" },
  pg_ro_timeout = { typ = "number" },
  pg_ro_password = { typ = "string" },
  pg_ro_ssl = { typ = "boolean" },
  pg_ro_ssl_verify = { typ = "boolean" },
  pg_ro_max_concurrent_queries = { typ = "number" },
  pg_ro_semaphore_timeout = { typ = "number" },

  cassandra_contact_points = { typ = "array" },
  cassandra_port = { typ = "number" },
  cassandra_password = { typ = "string" },
  cassandra_timeout = { typ = "number" },
  cassandra_ssl = { typ = "boolean" },
  cassandra_ssl_verify = { typ = "boolean" },
  cassandra_write_consistency = { enum = {
                                  "ALL",
                                  "EACH_QUORUM",
                                  "QUORUM",
                                  "LOCAL_QUORUM",
                                  "ONE",
                                  "TWO",
                                  "THREE",
                                  "LOCAL_ONE",
                                }
                              },
  cassandra_read_consistency = { enum = {
                                  "ALL",
                                  "EACH_QUORUM",
                                  "QUORUM",
                                  "LOCAL_QUORUM",
                                  "ONE",
                                  "TWO",
                                  "THREE",
                                  "LOCAL_ONE",
                                }
                              },
  cassandra_consistency = {
    typ = "string",
    deprecated = {
      replacement = "cassandra_write_consistency / cassandra_read_consistency",
      alias = function(conf)
        if conf.cassandra_write_consistency == nil then
          conf.cassandra_write_consistency = conf.cassandra_consistency
        end

        if conf.cassandra_read_consistency == nil then
          conf.cassandra_read_consistency = conf.cassandra_consistency
        end
      end,
    }
  },
  cassandra_lb_policy = { enum = {
                            "RoundRobin",
                            "RequestRoundRobin",
                            "DCAwareRoundRobin",
                            "RequestDCAwareRoundRobin",
                          }
                        },
  cassandra_local_datacenter = { typ = "string" },
  cassandra_refresh_frequency = { typ = "number" },
  cassandra_repl_strategy = { enum = {
                                "SimpleStrategy",
                                "NetworkTopologyStrategy",
                              }
                            },
  cassandra_repl_factor = { typ = "number" },
  cassandra_data_centers = { typ = "array" },
  cassandra_schema_consensus_timeout = { typ = "number" },

  dns_resolver = { typ = "array" },
  dns_hostsfile = { typ = "string" },
  dns_order = { typ = "array" },
  dns_valid_ttl = { typ = "number" },
  dns_stale_ttl = { typ = "number" },
  dns_not_found_ttl = { typ = "number" },
  dns_error_ttl = { typ = "number" },
  dns_no_sync = { typ = "boolean" },
  worker_consistency = { enum = { "strict", "eventual" } },
  router_consistency = {
    enum = { "strict", "eventual" },
    deprecated = {
      replacement = "worker_consistency",
      alias = function(conf)
        if conf.worker_consistency == nil and
           conf.router_consistency ~= nil then
          conf.worker_consistency = conf.router_consistency
        end
      end,
    }
  },
  worker_state_update_frequency = { typ = "number" },
  router_update_frequency = {
    typ = "number",
    deprecated = {
      replacement = "worker_state_update_frequency",
      alias = function(conf)
        if conf.worker_state_update_frequency == nil and
           conf.router_update_frequency ~= nil then
          conf.worker_state_update_frequency = conf.router_update_frequency
        end
      end,
    }
  },

  ssl_protocols = {
    typ = "string",
    directives = {
      "nginx_http_ssl_protocols",
      "nginx_stream_ssl_protocols",
    },
  },
  ssl_prefer_server_ciphers = {
    typ = "ngx_boolean",
    directives = {
      "nginx_http_ssl_prefer_server_ciphers",
      "nginx_stream_ssl_prefer_server_ciphers",
    },
  },
  ssl_dhparam = {
    typ = "string",
    directives = {
      "nginx_http_ssl_dhparam",
      "nginx_stream_ssl_dhparam",
    },
  },
  ssl_session_tickets = {
    typ = "ngx_boolean",
    directives = {
      "nginx_http_ssl_session_tickets",
      "nginx_stream_ssl_session_tickets",
    },
  },
  ssl_session_timeout = {
    typ = "string",
    directives = {
      "nginx_http_ssl_session_timeout",
      "nginx_stream_ssl_session_timeout",
    },
  },

  client_ssl = { typ = "boolean" },

  proxy_access_log = { typ = "string" },
  proxy_error_log = { typ = "string" },
  proxy_stream_access_log = { typ = "string" },
  proxy_stream_error_log = { typ = "string" },
  admin_access_log = { typ = "string" },
  admin_error_log = { typ = "string" },
  status_access_log = { typ = "string" },
  status_error_log = { typ = "string" },
  log_level = { enum = {
                  "debug",
                  "info",
                  "notice",
                  "warn",
                  "error",
                  "crit",
                  "alert",
                  "emerg",
                }
              },
  plugins = { typ = "array" },
  anonymous_reports = { typ = "boolean" },
  nginx_optimizations = {
    typ = "boolean",
    deprecated = { replacement = false }
  },

  lua_ssl_trusted_certificate = { typ = "array" },
  lua_ssl_verify_depth = { typ = "number" },
  lua_ssl_protocols = {
    typ = "string",
    directives = {
      "nginx_http_lua_ssl_protocols",
      "nginx_stream_lua_ssl_protocols",
    },
  },
  lua_socket_pool_size = { typ = "number" },

  role = { enum = { "data_plane", "control_plane", "traditional", }, },
  cluster_control_plane = { typ = "string", },
  cluster_cert = { typ = "string" },
  cluster_cert_key = { typ = "string" },
  cluster_mtls = { enum = { "shared", "pki" } },
  cluster_ca_cert = { typ = "string" },
  cluster_server_name = { typ = "string" },
  cluster_data_plane_purge_delay = { typ = "number" },
  cluster_ocsp = { enum = { "on", "off", "optional" } },
  cluster_v2 = { typ = "boolean", },

  kic = { typ = "boolean" },
  pluginserver_names = { typ = "array" },

  untrusted_lua = { enum = { "on", "off", "sandbox" } },
  untrusted_lua_sandbox_requires = { typ = "array" },
  untrusted_lua_sandbox_environment = { typ = "array" },
}


-- List of settings whose values must not be printed when
-- using the CLI in debug mode (which prints all settings).
local CONF_SENSITIVE_PLACEHOLDER = "******"
local CONF_SENSITIVE = {
  pg_password = true,
  pg_ro_password = true,
  cassandra_password = true,
}


local typ_checks = {
  array = function(v) return type(v) == "table" end,
  string = function(v) return type(v) == "string" end,
  number = function(v) return type(v) == "number" end,
  boolean = function(v) return type(v) == "boolean" end,
  ngx_boolean = function(v) return v == "on" or v == "off" end,
}


-- This meta table will prevent the parsed table to be passed on in the
-- intermediate Kong config file in the prefix directory.
-- We thus avoid 'table: 0x41c3fa58' from appearing into the prefix
-- hidden configuration file.
-- This is only to be applied to values that are injected into the
-- configuration object, and not configuration properties themselves,
-- otherwise we would prevent such properties from being specifiable
-- via environment variables.
local _nop_tostring_mt = {
  __tostring = function() return "" end,
}


-- Validate properties (type/enum/custom) and infer their type.
-- @param[type=table] conf The configuration table to treat.
local function check_and_infer(conf, opts)
  local errors = {}

  for k, value in pairs(conf) do
    local v_schema = CONF_INFERENCES[k] or {}
    local typ = v_schema.typ

    if type(value) == "string" then
      if not opts.from_kong_env then
        -- remove trailing comment, if any
        -- and remove escape chars from octothorpes
        value = string.gsub(value, "[^\\]#.-$", "")
        value = string.gsub(value, "\\#", "#")
      end

      value = pl_stringx.strip(value)
    end

    -- transform {boolean} values ("on"/"off" aliasing to true/false)
    -- transform {ngx_boolean} values ("on"/"off" aliasing to on/off)
    -- transform {explicit string} values (number values converted to strings)
    -- transform {array} values (comma-separated strings)
    if typ == "boolean" then
      value = value == true or value == "on" or value == "true"

    elseif typ == "ngx_boolean" then
      value = (value == "on" or value == true) and "on" or "off"

    elseif typ == "string" then
      value = tostring(value) -- forced string inference

    elseif typ == "number" then
      value = tonumber(value) -- catch ENV variables (strings) that are numbers

    elseif typ == "array" and type(value) == "string" then
      -- must check type because pl will already convert comma
      -- separated strings to tables (but not when the arr has
      -- only one element)
      value = setmetatable(pl_stringx.split(value, ","), nil) -- remove List mt

      for i = 1, #value do
        value[i] = pl_stringx.strip(value[i])
      end
    end

    if value == "" then
      -- unset values are removed
      value = nil
    end

    typ = typ or "string"

    if value and not typ_checks[typ](value) then
      errors[#errors + 1] = fmt("%s is not a %s: '%s'", k, typ,
                                tostring(value))

    elseif v_schema.enum and not tablex.find(v_schema.enum, value) then
      errors[#errors + 1] = fmt("%s has an invalid value: '%s' (%s)", k,
                              tostring(value), concat(v_schema.enum, ", "))

    end

    conf[k] = value
  end

  ---------------------
  -- custom validations
  ---------------------

  conf.host_ports = {}
  if conf.port_maps then
    local MIN_PORT = 1
    local MAX_PORT = 65535

    for _, port_map in ipairs(conf.port_maps) do
      local colpos = string.find(port_map, ":", nil, true)
      if not colpos then
        errors[#errors + 1] = "invalid port mapping (`port_maps`): " .. port_map

      else
        local host_port_str = string.sub(port_map, 1, colpos - 1)
        local host_port_num = tonumber(host_port_str, 10)
        local kong_port_str = string.sub(port_map, colpos + 1)
        local kong_port_num = tonumber(kong_port_str, 10)

        if  (host_port_num and host_port_num >= MIN_PORT and host_port_num <= MAX_PORT)
        and (kong_port_num and kong_port_num >= MIN_PORT and kong_port_num <= MAX_PORT)
        then
            conf.host_ports[kong_port_num] = host_port_num
            conf.host_ports[kong_port_str] = host_port_num
        else
          errors[#errors + 1] = "invalid port mapping (`port_maps`): " .. port_map
        end
      end
    end
  end

  if conf.database == "cassandra" then
    if string.find(conf.cassandra_lb_policy, "DCAware", nil, true)
       and not conf.cassandra_local_datacenter
    then
      errors[#errors + 1] = "must specify 'cassandra_local_datacenter' when " ..
                            conf.cassandra_lb_policy .. " policy is in use"
    end

    if conf.cassandra_refresh_frequency < 0 then
      errors[#errors + 1] = "cassandra_refresh_frequency must be 0 or greater"
    end

    for _, contact_point in ipairs(conf.cassandra_contact_points) do
      local endpoint, err = utils.normalize_ip(contact_point)
      if not endpoint then
        errors[#errors + 1] = fmt("bad cassandra contact point '%s': %s",
                                  contact_point, err)

      elseif endpoint.port then
        errors[#errors + 1] = fmt("bad cassandra contact point '%s': %s",
                                  contact_point,
                                  "port must be specified in cassandra_port")
      end
    end

    -- cache settings check

    if conf.db_update_propagation == 0 then
      log.warn("You are using Cassandra but your 'db_update_propagation' " ..
               "setting is set to '0' (default). Due to the distributed "  ..
               "nature of Cassandra, you should increase this value.")
    end
  end

  for _, prefix in ipairs({ "proxy_", "admin_", "status_" }) do
    local listen = conf[prefix .. "listen"]

    local ssl_enabled = (concat(listen, ",") .. " "):find("%sssl[%s,]") ~= nil
    if not ssl_enabled and prefix == "proxy_" then
      ssl_enabled = (concat(conf.stream_listen, ",") .. " "):find("%sssl[%s,]") ~= nil
    end

    if prefix == "proxy_" then
      prefix = ""
    end

    if ssl_enabled then
      conf.ssl_enabled = true

      local ssl_cert = conf[prefix .. "ssl_cert"]
      local ssl_cert_key = conf[prefix .. "ssl_cert_key"]

      if #ssl_cert > 0 and #ssl_cert_key == 0 then
        errors[#errors + 1] = prefix .. "ssl_cert_key must be specified"

      elseif #ssl_cert_key > 0 and #ssl_cert == 0 then
        errors[#errors + 1] = prefix .. "ssl_cert must be specified"

      elseif #ssl_cert ~= #ssl_cert_key then
        errors[#errors + 1] = prefix .. "ssl_cert was specified " .. #ssl_cert .. " times while " ..
          prefix .. "ssl_cert_key was specified " .. #ssl_cert_key .. " times"
      end

      if ssl_cert then
        for _, cert in ipairs(ssl_cert) do
          if not pl_path.exists(cert) then
            errors[#errors + 1] = prefix .. "ssl_cert: no such file at " .. cert
          end
        end
      end

      if ssl_cert_key then
        for _, cert_key in ipairs(ssl_cert_key) do
          if not pl_path.exists(cert_key) then
            errors[#errors + 1] = prefix .. "ssl_cert_key: no such file at " .. cert_key
          end
        end
      end
    end
  end

  if conf.client_ssl then
    if conf.client_ssl_cert and not conf.client_ssl_cert_key then
      errors[#errors + 1] = "client_ssl_cert_key must be specified"

    elseif conf.client_ssl_cert_key and not conf.client_ssl_cert then
      errors[#errors + 1] = "client_ssl_cert must be specified"
    end

    if conf.client_ssl_cert and not pl_path.exists(conf.client_ssl_cert) then
      errors[#errors + 1] = "client_ssl_cert: no such file at " ..
                          conf.client_ssl_cert
    end

    if conf.client_ssl_cert_key and not pl_path.exists(conf.client_ssl_cert_key) then
      errors[#errors + 1] = "client_ssl_cert_key: no such file at " ..
                          conf.client_ssl_cert_key
    end
  end

  if conf.lua_ssl_trusted_certificate then
    local new_paths = {}

    for i, path in ipairs(conf.lua_ssl_trusted_certificate) do
      if path == "system" then
        local system_path, err = utils.get_system_trusted_certs_filepath()
        if system_path then
          path = system_path

        else
          errors[#errors + 1] =
            "lua_ssl_trusted_certificate: unable to locate system bundle - " ..
            err
        end
      end

      if not pl_path.exists(path) then
        errors[#errors + 1] = "lua_ssl_trusted_certificate: no such file at " ..
                               path
      end

      new_paths[i] = path
    end

    conf.lua_ssl_trusted_certificate = new_paths
  end

  if conf.ssl_cipher_suite ~= "custom" then
    local suite = cipher_suites[conf.ssl_cipher_suite]
    if suite then
      conf.ssl_ciphers = suite.ciphers
      conf.nginx_http_ssl_protocols = suite.protocols
      conf.nginx_http_ssl_prefer_server_ciphers = suite.prefer_server_ciphers
      conf.nginx_stream_ssl_protocols = suite.protocols
      conf.nginx_stream_ssl_prefer_server_ciphers = suite.prefer_server_ciphers

      -- There is no secure predefined one for old at the moment (and it's too slow to generate one).
      -- Intermediate (the default) forcibly sets this to predefined ffdhe2048 group.
      -- Modern just forcibly sets this to nil as there are no ciphers that need it.
      if conf.ssl_cipher_suite ~= "old" then
        conf.ssl_dhparam = suite.dhparams
        conf.nginx_http_ssl_dhparam = suite.dhparams
        conf.nginx_stream_ssl_dhparam = suite.dhparams
      end

    else
      errors[#errors + 1] = "Undefined cipher suite " .. tostring(conf.ssl_cipher_suite)
    end
  end

  if conf.ssl_dhparam then
    if not is_predefined_dhgroup(conf.ssl_dhparam) and not pl_path.exists(conf.ssl_dhparam) then
      errors[#errors + 1] = "ssl_dhparam: no such file at " .. conf.ssl_dhparam
    end

  else
    for _, key in ipairs({ "nginx_http_ssl_dhparam", "nginx_stream_ssl_dhparam" }) do
      local file = conf[key]
      if file and not is_predefined_dhgroup(file) and not pl_path.exists(file) then
        errors[#errors + 1] = key .. ": no such file at " .. file
      end
    end
  end

  if conf.headers then
    for _, token in ipairs(conf.headers) do
      if token ~= "off" and not HEADER_KEY_TO_NAME[string.lower(token)] then
        errors[#errors + 1] = fmt("headers: invalid entry '%s'",
                                  tostring(token))
      end
    end
  end

  if conf.dns_resolver then
    for _, server in ipairs(conf.dns_resolver) do
      local dns = utils.normalize_ip(server)

      if not dns or dns.type == "name" then
        errors[#errors + 1] = "dns_resolver must be a comma separated list " ..
                              "in the form of IPv4/6 or IPv4/6:port, got '"  ..
                              server .. "'"
      end
    end
  end

  if conf.dns_hostsfile then
    if not pl_path.isfile(conf.dns_hostsfile) then
      errors[#errors + 1] = "dns_hostsfile: file does not exist"
    end
  end

  if conf.dns_order then
    local allowed = { LAST = true, A = true, CNAME = true,
                      SRV = true, AAAA = true }

    for _, name in ipairs(conf.dns_order) do
      if not allowed[name:upper()] then
        errors[#errors + 1] = fmt("dns_order: invalid entry '%s'",
                                  tostring(name))
      end
      if name:upper() == "AAAA" then
        log.warn("the 'dns_order' configuration property specifies the " ..
                 "experimental IPv6 entry 'AAAA'")

      end
    end
  end

  if not conf.lua_package_cpath then
    conf.lua_package_cpath = ""
  end

  -- checking the trusted ips
  for _, address in ipairs(conf.trusted_ips) do
    if not utils.is_valid_ip_or_cidr(address) and address ~= "unix:" then
      errors[#errors + 1] = "trusted_ips must be a comma separated list in " ..
                            "the form of IPv4 or IPv6 address or CIDR "      ..
                            "block or 'unix:', got '" .. address .. "'"
    end
  end

  if conf.pg_max_concurrent_queries < 0 then
    errors[#errors + 1] = "pg_max_concurrent_queries must be greater than 0"
  end

  if conf.pg_max_concurrent_queries ~= math.floor(conf.pg_max_concurrent_queries) then
    errors[#errors + 1] = "pg_max_concurrent_queries must be an integer greater than 0"
  end

  if conf.pg_semaphore_timeout < 0 then
    errors[#errors + 1] = "pg_semaphore_timeout must be greater than 0"
  end

  if conf.pg_semaphore_timeout ~= math.floor(conf.pg_semaphore_timeout) then
    errors[#errors + 1] = "pg_semaphore_timeout must be an integer greater than 0"
  end

  if conf.pg_ro_max_concurrent_queries then
    if conf.pg_ro_max_concurrent_queries < 0 then
      errors[#errors + 1] = "pg_ro_max_concurrent_queries must be greater than 0"
    end

    if conf.pg_ro_max_concurrent_queries ~= math.floor(conf.pg_ro_max_concurrent_queries) then
      errors[#errors + 1] = "pg_ro_max_concurrent_queries must be an integer greater than 0"
    end
  end

  if conf.pg_ro_semaphore_timeout then
    if conf.pg_ro_semaphore_timeout < 0 then
      errors[#errors + 1] = "pg_ro_semaphore_timeout must be greater than 0"
    end

    if conf.pg_ro_semaphore_timeout ~= math.floor(conf.pg_ro_semaphore_timeout) then
      errors[#errors + 1] = "pg_ro_semaphore_timeout must be an integer greater than 0"
    end
  end

  if conf.worker_state_update_frequency <= 0 then
    errors[#errors + 1] = "worker_state_update_frequency must be greater than 0"
  end

  if conf.role == "control_plane" then
    if #conf.admin_listen < 1 or pl_stringx.strip(conf.admin_listen[1]) == "off" then
      errors[#errors + 1] = "admin_listen must be specified when role = \"control_plane\""
    end

    if conf.cluster_mtls == "pki" and not conf.cluster_ca_cert then
      errors[#errors + 1] = "cluster_ca_cert must be specified when cluster_mtls = \"pki\""
    end

    if #conf.cluster_listen < 1 or pl_stringx.strip(conf.cluster_listen[1]) == "off" then
      errors[#errors + 1] = "cluster_listen must be specified when role = \"control_plane\""
    end

    if conf.database == "off" then
      errors[#errors + 1] = "in-memory storage can not be used when role = \"control_plane\""
    end

  elseif conf.role == "data_plane" then
    if #conf.proxy_listen < 1 or pl_stringx.strip(conf.proxy_listen[1]) == "off" then
      errors[#errors + 1] = "proxy_listen must be specified when role = \"data_plane\""
    end

    if conf.database ~= "off" then
      errors[#errors + 1] = "only in-memory storage can be used when role = \"data_plane\"\n" ..
                            "Hint: set database = off in your kong.conf"
    end

    if not conf.lua_ssl_trusted_certificate then
      conf.lua_ssl_trusted_certificate = {}
    end

    if conf.cluster_mtls == "shared" then
      table.insert(conf.lua_ssl_trusted_certificate, conf.cluster_cert)

    elseif conf.cluster_mtls == "pki" then
      table.insert(conf.lua_ssl_trusted_certificate, conf.cluster_ca_cert)
    end
  end

  if conf.cluster_data_plane_purge_delay < 60 then
    errors[#errors + 1] = "cluster_data_plane_purge_delay must be 60 or greater"
  end

  if conf.role == "control_plane" or conf.role == "data_plane" then
    if not conf.cluster_cert or not conf.cluster_cert_key then
      errors[#errors + 1] = "cluster certificate and key must be provided to use Hybrid mode"

    else
      if not pl_path.exists(conf.cluster_cert) then
        errors[#errors + 1] = "cluster_cert: no such file at " ..
                              conf.cluster_cert
      end

      if not pl_path.exists(conf.cluster_cert_key) then
        errors[#errors + 1] = "cluster_cert_key: no such file at " ..
                              conf.cluster_cert_key
      end
    end
  end

  if conf.upstream_keepalive_pool_size < 0 then
    errors[#errors + 1] = "upstream_keepalive_pool_size must be 0 or greater"
  end

  if conf.upstream_keepalive_max_requests < 0 then
    errors[#errors + 1] = "upstream_keepalive_max_requests must be 0 or greater"
  end

  if conf.upstream_keepalive_idle_timeout < 0 then
    errors[#errors + 1] = "upstream_keepalive_idle_timeout must be 0 or greater"
  end

  return #errors == 0, errors[1], errors
end


local function overrides(k, default_v, opts, file_conf, arg_conf)
  opts = opts or {}

  local value -- definitive value for this property
  local escape -- whether to escape a value's octothorpes

  -- default values have lowest priority

  if file_conf and file_conf[k] == nil and not opts.no_defaults then
    -- PL will ignore empty strings, so we need a placeholder (NONE)
    value = default_v == "NONE" and "" or default_v

  else
    value = file_conf[k] -- given conf values have middle priority
  end

  if opts.defaults_only then
    return value, k
  end

  if not opts.from_kong_env then
    -- environment variables have higher priority

    local env_name = "KONG_" .. string.upper(k)
    local env = os.getenv(env_name)
    if env ~= nil then
      local to_print = env

      if CONF_SENSITIVE[k] then
        to_print = CONF_SENSITIVE_PLACEHOLDER
      end

      log.debug('%s ENV found with "%s"', env_name, to_print)

      value = env
      escape = true
    end
  end

  -- arg_conf have highest priority
  if arg_conf and arg_conf[k] ~= nil then
    value = arg_conf[k]
    escape = true
  end

  if escape and type(value) == "string" then
    -- Escape "#" in env vars or overrides to avoid them being mangled by
    -- comments stripping logic.
    repeat
      local s, n = string.gsub(value, [[([^\])#]], [[%1\#]])
      value = s
    until n == 0
  end

  return value, k
end


local function parse_nginx_directives(dyn_namespace, conf, injected_in_namespace)
  conf = conf or {}
  local directives = {}

  for k, v in pairs(conf) do
    if type(k) == "string" and not injected_in_namespace[k] then
      local directive = string.match(k, dyn_namespace.prefix .. "(.+)")
      if directive then
        if v ~= "NONE" and not dyn_namespace.ignore[directive] then
          table.insert(directives, { name = directive, value = v })
        end

        injected_in_namespace[k] = true
      end
    end
  end

  return directives
end


local function aliased_properties(conf)
  for property_name, v_schema in pairs(CONF_INFERENCES) do
    local alias = v_schema.alias

    if alias and conf[property_name] ~= nil and conf[alias.replacement] == nil then
      if alias.alias then
        conf[alias.replacement] = alias.alias(conf)
      else
        local value = conf[property_name]
        if type(value) == "boolean" then
          value = value and "on" or "off"
        end
        conf[alias.replacement] = tostring(value)
      end
    end
  end
end


local function deprecated_properties(conf, opts)
  for property_name, v_schema in pairs(CONF_INFERENCES) do
    local deprecated = v_schema.deprecated

    if deprecated and conf[property_name] ~= nil then
      if not opts.from_kong_env then
        if deprecated.replacement then
          log.warn("the '%s' configuration property is deprecated, use " ..
                     "'%s' instead", property_name, deprecated.replacement)
        else
          log.warn("the '%s' configuration property is deprecated",
                   property_name)
        end
      end

      if deprecated.alias then
        deprecated.alias(conf)
      end
    end
  end
end


local function dynamic_properties(conf)
  for property_name, v_schema in pairs(CONF_INFERENCES) do
    local value = conf[property_name]
    if value ~= nil then
      local directives = v_schema.directives
      if directives then
        for _, directive in ipairs(directives) do
          if not conf[directive] then
            if type(value) == "boolean" then
              value = value and "on" or "off"
            end
            conf[directive] = value
          end
        end
      end
    end
  end
end


--- Load Kong configuration file
-- The loaded configuration will only contain properties read from the
-- passed configuration file (properties are not merged with defaults or
-- environment variables)
-- @param[type=string] Path to a configuration file.
local function load_config_file(path)
  assert(type(path) == "string")

  local f, err = pl_file.read(path)
  if not f then
    return nil, err
  end

  local s = pl_stringio.open(f)
  local conf, err = pl_config.read(s, {
    smart = false,
    list_delim = "_blank_" -- mandatory but we want to ignore it
  })
  s:close()
  if not conf then
    return nil, err
  end

  return conf
end


--- Load Kong configuration
-- The loaded configuration will have all properties from the default config
-- merged with the (optionally) specified config file, environment variables
-- and values specified in the `custom_conf` argument.
-- Values will then be validated and additional values (such as `proxy_port` or
-- `plugins`) will be appended to the final configuration table.
-- @param[type=string] path (optional) Path to a configuration file.
-- @param[type=table] custom_conf A key/value table with the highest precedence.
-- @treturn table A table holding a valid configuration.
local function load(path, custom_conf, opts)
  opts = opts or {}

  ------------------------
  -- Default configuration
  ------------------------

  -- load defaults, they are our mandatory base
  local s = pl_stringio.open(kong_default_conf)
  local defaults, err = pl_config.read(s, {
    smart = false,
    list_delim = "_blank_" -- mandatory but we want to ignore it
  })
  s:close()
  if not defaults then
    return nil, "could not load default conf: " .. err
  end

  ---------------------
  -- Configuration file
  ---------------------

  local from_file_conf = {}
  if path and not pl_path.exists(path) then
    -- file conf has been specified and must exist
    return nil, "no file at: " .. path
  end

  if not path then
    -- try to look for a conf in default locations, but no big
    -- deal if none is found: we will use our defaults.
    for _, default_path in ipairs(DEFAULT_PATHS) do
      if pl_path.exists(default_path) then
        path = default_path
        break
      end

      log.verbose("no config file found at %s", default_path)
    end
  end

  if not path then
    -- still no file in default locations
    log.verbose("no config file, skip loading")

  else
    log.verbose("reading config file at %s", path)

    from_file_conf = load_config_file(path)
  end

  -----------------------
  -- Merging & validation
  -----------------------

  do
    -- find dynamic keys that need to be loaded
    local dynamic_keys = {}

    local function add_dynamic_keys(t)
      t = t or {}

      for property_name, v_schema in pairs(CONF_INFERENCES) do
        local directives = v_schema.directives
        if directives then
          local v = t[property_name]
          if v then
            if type(v) == "boolean" then
              v = v and "on" or "off"
            end

            tostring(v)

            for _, directive in ipairs(directives) do
              dynamic_keys[directive] = true
              t[directive] = v
            end
          end
        end
      end
    end

    local function find_dynamic_keys(dyn_prefix, t)
      t = t or {}

      for k, v in pairs(t) do
        local directive = string.match(k, "^(" .. dyn_prefix .. ".+)")
        if directive then
          dynamic_keys[directive] = true

          if type(v) == "boolean" then
            v = v and "on" or "off"
          end

          t[k] = tostring(v)
        end
      end
    end

    local kong_env_vars = {}

    do
      -- get env vars prefixed with KONG_<dyn_key_prefix>
      local env_vars, err = env.read_all()
      if err then
        return nil, err
      end

      for k, v in pairs(env_vars) do
        local kong_var = string.match(string.lower(k), "^kong_(.+)")
        if kong_var then
          -- the value will be read in `overrides()`
          kong_env_vars[kong_var] = true
        end
      end
    end

    add_dynamic_keys(defaults)
    add_dynamic_keys(custom_conf)
    add_dynamic_keys(kong_env_vars)
    add_dynamic_keys(from_file_conf)

    for _, dyn_namespace in ipairs(DYNAMIC_KEY_NAMESPACES) do
      find_dynamic_keys(dyn_namespace.prefix, defaults) -- tostring() defaults
      find_dynamic_keys(dyn_namespace.prefix, custom_conf)
      find_dynamic_keys(dyn_namespace.prefix, kong_env_vars)
      find_dynamic_keys(dyn_namespace.prefix, from_file_conf)
    end

    -- union (add dynamic keys to `defaults` to prevent removal of the keys
    -- during the intersection that happens later)
    defaults = tablex.merge(dynamic_keys, defaults, true)
  end

  -- merge file conf, ENV variables, and arg conf (with precedence)
  local user_conf = tablex.pairmap(overrides, defaults,
                                   tablex.union(opts, { no_defaults = true, }),
                                   from_file_conf, custom_conf)

  if not opts.starting then
    log.disable()
  end

  aliased_properties(user_conf)
  dynamic_properties(user_conf)
  deprecated_properties(user_conf, opts)

  -- merge user_conf with defaults
  local conf = tablex.pairmap(overrides, defaults,
                              tablex.union(opts, { defaults_only = true, }),
                              user_conf)

  -- validation
  local ok, err, errors = check_and_infer(conf, opts)

  if not opts.starting then
    log.enable()
  end

  if not ok then
    return nil, err, errors
  end

  conf = tablex.merge(conf, defaults) -- intersection (remove extraneous properties)

  local default_nginx_main_user = false
  local default_nginx_user = false

  do
    -- nginx 'user' directive
    local user = utils.strip(conf.nginx_main_user):gsub("%s+", " ")
    if user == "nobody" or user == "nobody nobody" then
      conf.nginx_main_user = nil

    elseif user == "kong" or user == "kong kong" then
      default_nginx_main_user = true
    end

    local user = utils.strip(conf.nginx_user):gsub("%s+", " ")
    if user == "nobody" or user == "nobody nobody" then
      conf.nginx_user = nil

    elseif user == "kong" or user == "kong kong" then
      default_nginx_user = true
    end
  end

  if C.getpwnam("kong") == nil or C.getgrnam("kong") == nil then
    if default_nginx_main_user == true and default_nginx_user == true then
      conf.nginx_user = nil
      conf.nginx_main_user = nil
    end
  end

  do
    local injected_in_namespace = {}

    -- nginx directives from conf
    for _, dyn_namespace in ipairs(DYNAMIC_KEY_NAMESPACES) do
      if dyn_namespace.injected_conf_name then
        injected_in_namespace[dyn_namespace.injected_conf_name] = true

        local directives = parse_nginx_directives(dyn_namespace, conf,
          injected_in_namespace)
        conf[dyn_namespace.injected_conf_name] = setmetatable(directives,
          _nop_tostring_mt)
      end
    end

    -- TODO: Deprecated, but kept for backward compatibility.
    for _, dyn_namespace in ipairs(DEPRECATED_DYNAMIC_KEY_NAMESPACES) do
      if conf[dyn_namespace.injected_conf_name] then
        conf[dyn_namespace.previous_conf_name] = conf[dyn_namespace.injected_conf_name]
      end
    end
  end

  do
    -- print alphabetically-sorted values
    local conf_arr = {}

    for k, v in pairs(conf) do
      local to_print = v
      if CONF_SENSITIVE[k] then
        to_print = "******"
      end

      conf_arr[#conf_arr+1] = k .. " = " .. pl_pretty.write(to_print, "")
    end

    table.sort(conf_arr)

    for i = 1, #conf_arr do
      log.debug(conf_arr[i])
    end
  end

  -----------------------------
  -- Additional injected values
  -----------------------------

  do
    -- merge plugins
    local plugins = {}

    if #conf.plugins > 0 and conf.plugins[1] ~= "off" then
      for i = 1, #conf.plugins do
        local plugin_name = pl_stringx.strip(conf.plugins[i])

        if plugin_name ~= "off" then
          if plugin_name == "bundled" then
            plugins = tablex.merge(constants.BUNDLED_PLUGINS, plugins, true)

          else
            plugins[plugin_name] = true
          end
        end
      end
    end

    conf.loaded_plugins = setmetatable(plugins, _nop_tostring_mt)
  end

  -- temporary workaround: inject an shm for prometheus plugin if needed
  -- TODO: allow plugins to declare shm dependencies that are automatically
  -- injected
  if conf.loaded_plugins["prometheus"] then
    local http_directives = conf["nginx_http_directives"]
    local found = false

    for _, directive in pairs(http_directives) do
      if directive.name == "lua_shared_dict"
         and string.find(directive.value, "prometheus_metrics", nil, true)
      then
         found = true
         break
      end
    end

    if not found then
      table.insert(http_directives, {
        name  = "lua_shared_dict",
        value = "prometheus_metrics 5m",
      })
    end

    local stream_directives = conf["nginx_stream_directives"]
    local found = false

    for _, directive in pairs(stream_directives) do
      if directive.name == "lua_shared_dict"
        and string.find(directive.value, "stream_prometheus_metrics", nil, true)
      then
        found = true
        break
      end
    end

    if not found then
      table.insert(stream_directives, {
        name  = "lua_shared_dict",
        value = "stream_prometheus_metrics 5m",
      })
    end
  end

  for _, dyn_namespace in ipairs(DYNAMIC_KEY_NAMESPACES) do
    if dyn_namespace.injected_conf_name then
      table.sort(conf[dyn_namespace.injected_conf_name], function(a, b)
        return a.name < b.name
      end)
    end
  end

  ok, err = listeners.parse(conf, {
    { name = "proxy_listen",   subsystem = "http",   ssl_flag = "proxy_ssl_enabled" },
    { name = "stream_listen",  subsystem = "stream", ssl_flag = "stream_proxy_ssl_enabled" },
    { name = "admin_listen",   subsystem = "http",   ssl_flag = "admin_ssl_enabled" },
    { name = "status_listen",  flags = { "ssl" },    ssl_flag = "status_ssl_enabled" },
    { name = "cluster_listen", subsystem = "http" },
  })
  if not ok then
    return nil, err
  end

  do
    -- load headers configuration
    local enabled_headers = {}

    for _, v in pairs(HEADER_KEY_TO_NAME) do
      enabled_headers[v] = false
    end

    if #conf.headers > 0 and conf.headers[1] ~= "off" then
      for _, token in ipairs(conf.headers) do
        if token ~= "off" then
          enabled_headers[HEADER_KEY_TO_NAME[string.lower(token)]] = true
        end
      end
    end

    if enabled_headers.server_tokens then
      enabled_headers[HEADERS.VIA] = true
      enabled_headers[HEADERS.SERVER] = true
    end

    if enabled_headers.latency_tokens then
      enabled_headers[HEADERS.PROXY_LATENCY] = true
      enabled_headers[HEADERS.RESPONSE_LATENCY] = true
      enabled_headers[HEADERS.ADMIN_LATENCY] = true
      enabled_headers[HEADERS.UPSTREAM_LATENCY] = true
    end

    conf.enabled_headers = setmetatable(enabled_headers, _nop_tostring_mt)
  end

  -- load absolute paths
  conf.prefix = pl_path.abspath(conf.prefix)

  for _, prefix in ipairs({ "ssl", "admin_ssl", "status_ssl", "client_ssl", "cluster" }) do
    local ssl_cert = conf[prefix .. "_cert"]
    local ssl_cert_key = conf[prefix .. "_cert_key"]

    if ssl_cert and ssl_cert_key then
      if type(ssl_cert) == "table" then
        for i, cert in ipairs(ssl_cert) do
          ssl_cert[i] = pl_path.abspath(cert)
        end

      else
        conf[prefix .. "_cert"] = pl_path.abspath(ssl_cert)
      end

      if type(ssl_cert) == "table" then
        for i, key in ipairs(ssl_cert_key) do
          ssl_cert_key[i] = pl_path.abspath(key)
        end

      else
        conf[prefix .. "_cert_key"] = pl_path.abspath(ssl_cert_key)
      end
    end
  end

  if conf.cluster_ca_cert then
    conf.cluster_ca_cert = pl_path.abspath(conf.cluster_ca_cert)
  end

  local ssl_enabled = conf.proxy_ssl_enabled or
                      conf.stream_proxy_ssl_enabled or
                      conf.admin_ssl_enabled or
                      conf.status_ssl_enabled

  for _, name in ipairs({ "nginx_http_directives", "nginx_stream_directives" }) do
    for i, directive in ipairs(conf[name]) do
      if directive.name == "ssl_dhparam" then
        if is_predefined_dhgroup(directive.value) then
          if ssl_enabled then
            directive.value = pl_path.abspath(pl_path.join(conf.prefix, "ssl", directive.value .. ".pem"))

          else
            table.remove(conf[name], i)
          end

        else
          directive.value = pl_path.abspath(directive.value)
        end

        break
      end
    end
  end

  if conf.lua_ssl_trusted_certificate
     and #conf.lua_ssl_trusted_certificate > 0 then
    conf.lua_ssl_trusted_certificate =
      tablex.map(pl_path.abspath, conf.lua_ssl_trusted_certificate)

    conf.lua_ssl_trusted_certificate_combined =
      pl_path.abspath(pl_path.join(conf.prefix, ".ca_combined"))
  end

  -- attach prefix files paths
  for property, t_path in pairs(PREFIX_PATHS) do
    conf[property] = pl_path.join(conf.prefix, unpack(t_path))
  end

  log.verbose("prefix in use: %s", conf.prefix)

  -- initialize the dns client, so the globally patched tcp.connect method
  -- will work from here onwards.
  assert(require("kong.tools.dns")(conf))

  return setmetatable(conf, nil) -- remove Map mt
end


return setmetatable({
  load = load,

  load_config_file = load_config_file,

  add_default_path = function(path)
    DEFAULT_PATHS[#DEFAULT_PATHS+1] = path
  end,

  remove_sensitive = function(conf)
    local purged_conf = tablex.deepcopy(conf)

    for k in pairs(CONF_SENSITIVE) do
      if purged_conf[k] then
        purged_conf[k] = CONF_SENSITIVE_PLACEHOLDER
      end
    end

    return purged_conf
  end,
}, {
  __call = function(_, ...)
    return load(...)
  end,
})
