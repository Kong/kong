local require = require


local kong_default_conf = require "kong.templates.kong_defaults"
local process_secrets = require "kong.cmd.utils.process_secrets"
local openssl_pkey = require "resty.openssl.pkey"
local openssl_x509 = require "resty.openssl.x509"
local pl_stringio = require "pl.stringio"
local pl_stringx = require "pl.stringx"
local socket_url = require "socket.url"
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
local sub = string.sub
local type = type
local sort = table.sort
local find = string.find
local gsub = string.gsub
local strip = pl_stringx.strip
local floor = math.floor
local lower = string.lower
local upper = string.upper
local match = string.match
local pairs = pairs
local assert = assert
local unpack = unpack
local ipairs = ipairs
local insert = table.insert
local remove = table.remove
local concat = table.concat
local getenv = os.getenv
local exists = pl_path.exists
local abspath = pl_path.abspath
local tostring = tostring
local tonumber = tonumber
local setmetatable = setmetatable
local try_decode_base64 = utils.try_decode_base64


local get_phase do
  if ngx and ngx.get_phase then
    get_phase = ngx.get_phase
  else
    get_phase = function()
      return "timer"
    end
  end
end


local C = ffi.C


ffi.cdef([[
  struct group *getgrnam(const char *name);
  struct passwd *getpwnam(const char *name);
  int unsetenv(const char *name);
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
  },
                     fips = { -- https://wiki.openssl.org/index.php/FIPS_mode_and_TLS
                          -- TLSv1.0 and TLSv1.1 is not completely not FIPS compliant,
                          -- but must be used under certain condititions like key sizes,
                          -- signatures in the full chain that Kong can't control.
                          -- In that case, we disables TLSv1.0 and TLSv1.1 and user
                          -- can optionally turn them on if they are aware of the caveats.
                          -- No FIPS compliant predefined DH group available prior to
                          -- OpenSSL 3.0.
                protocols = "TLSv1.2",
                  ciphers = "TLSv1.2+FIPS:kRSA+FIPS:!eNULL:!aNULL",
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
  [lower(HEADERS.VIA)] = HEADERS.VIA,
  [lower(HEADERS.SERVER)] = HEADERS.SERVER,
  [lower(HEADERS.PROXY_LATENCY)] = HEADERS.PROXY_LATENCY,
  [lower(HEADERS.RESPONSE_LATENCY)] = HEADERS.RESPONSE_LATENCY,
  [lower(HEADERS.ADMIN_LATENCY)] = HEADERS.ADMIN_LATENCY,
  [lower(HEADERS.UPSTREAM_LATENCY)] = HEADERS.UPSTREAM_LATENCY,
  [lower(HEADERS.UPSTREAM_STATUS)] = HEADERS.UPSTREAM_STATUS,
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
  {
    prefix = "vault_",
    ignore = EMPTY,
  },
}


local DEPRECATED_DYNAMIC_KEY_NAMESPACES = {}


local PREFIX_PATHS = {
  nginx_pid = {"pids", "nginx.pid"},
  nginx_err_logs = {"logs", "error.log"},
  nginx_acc_logs = {"logs", "access.log"},
  admin_acc_logs = {"logs", "admin_access.log"},
  nginx_conf = {"nginx.conf"},
  nginx_kong_conf = {"nginx-kong.conf"},
  nginx_kong_stream_conf = {"nginx-kong-stream.conf"},

  kong_env = {".kong_env"},
  kong_process_secrets = {".kong_process_secrets"},

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
local CONF_PARSERS = {
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

  upstream_keepalive_pool_size = { typ = "number" },
  upstream_keepalive_max_requests = { typ = "number" },
  upstream_keepalive_idle_timeout = { typ = "number" },
  allow_debug_header = { typ = "boolean" },

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
  pg_keepalive_timeout = { typ = "number" },
  pg_pool_size = { typ = "number" },
  pg_backlog = { typ = "number" },
  pg_expired_rows_cleanup_interval = { typ = "number" },

  pg_ro_port = { typ = "number" },
  pg_ro_timeout = { typ = "number" },
  pg_ro_password = { typ = "string" },
  pg_ro_ssl = { typ = "boolean" },
  pg_ro_ssl_verify = { typ = "boolean" },
  pg_ro_max_concurrent_queries = { typ = "number" },
  pg_ro_semaphore_timeout = { typ = "number" },
  pg_ro_keepalive_timeout = { typ = "number" },
  pg_ro_pool_size = { typ = "number" },
  pg_ro_backlog = { typ = "number" },

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
  dns_cache_size = { typ = "number" },
  dns_not_found_ttl = { typ = "number" },
  dns_error_ttl = { typ = "number" },
  dns_no_sync = { typ = "boolean" },
  worker_consistency = { enum = { "strict", "eventual" },
    -- deprecating values for enums
    deprecated = {
      value = "strict",
     }
  },
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
  router_flavor = {
    enum = { "traditional", "traditional_compatible", "expressions" },
  },
  worker_state_update_frequency = { typ = "number" },

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
  ssl_session_cache_size = { typ = "string" },

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
  vaults = { typ = "array" },
  plugins = { typ = "array" },
  anonymous_reports = { typ = "boolean" },

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
  cluster_max_payload = { typ = "number" },
  cluster_use_proxy = { typ = "boolean" },

  kic = { typ = "boolean" },
  pluginserver_names = { typ = "array" },

  untrusted_lua = { enum = { "on", "off", "sandbox" } },
  untrusted_lua_sandbox_requires = { typ = "array" },
  untrusted_lua_sandbox_environment = { typ = "array" },

  legacy_worker_events = { typ = "boolean" },

  lmdb_environment_path = { typ = "string" },
  lmdb_map_size = { typ = "string" },

  opentelemetry_tracing = {
    typ = "array",
    alias = {
      replacement = "tracing_instrumentations",
    },
    deprecated = {
      replacement = "tracing_instrumentations",
    },
  },

  tracing_instrumentations = {
    typ = "array",
  },

  opentelemetry_tracing_sampling_rate = {
    typ = "number",
    deprecated = {
      replacement = "tracing_sampling_rate",
    },
    alias = {
      replacement = "tracing_sampling_rate",
    },
  },

  tracing_sampling_rate = {
    typ = "number",
  },

  proxy_server = { typ = "string" },
  proxy_server_ssl_verify = { typ = "boolean" },
}


-- List of settings whose values must not be printed when
-- using the CLI in debug mode (which prints all settings).
local CONF_SENSITIVE_PLACEHOLDER = "******"
local CONF_SENSITIVE = {
  pg_password = true,
  pg_ro_password = true,
  cassandra_password = true,
  proxy_server = true, -- hide proxy server URL as it may contain credentials
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


local function parse_value(value, typ)
  if type(value) == "string" then
    value = strip(value)
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
      value[i] = strip(value[i])
    end
  end

  if value == "" then
    -- unset values are removed
    value = nil
  end

  return value
end


-- Validate properties (type/enum/custom) and infer their type.
-- @param[type=table] conf The configuration table to treat.
local function check_and_parse(conf, opts)
  local errors = {}

  for k, value in pairs(conf) do
    local v_schema = CONF_PARSERS[k] or {}

    value = parse_value(value, v_schema.typ)

    local typ = v_schema.typ or "string"
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
      local colpos = find(port_map, ":", nil, true)
      if not colpos then
        errors[#errors + 1] = "invalid port mapping (`port_maps`): " .. port_map

      else
        local host_port_str = sub(port_map, 1, colpos - 1)
        local host_port_num = tonumber(host_port_str, 10)
        local kong_port_str = sub(port_map, colpos + 1)
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
    log.deprecation("Support for Cassandra is deprecated. Please refer to " ..
                    "https://konghq.com/blog/cassandra-support-deprecated", {
      after   = "2.7",
      removal = "4.0"
    })

    if find(conf.cassandra_lb_policy, "DCAware", nil, true)
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

    local ssl_enabled = find(concat(listen, ",") .. " ", "%sssl[%s,]") ~= nil
    if not ssl_enabled and prefix == "proxy_" then
      ssl_enabled = find(concat(conf.stream_listen, ",") .. " ", "%sssl[%s,]") ~= nil
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
        for i, cert in ipairs(ssl_cert) do
          if not exists(cert) then
            cert = try_decode_base64(cert)
            ssl_cert[i] = cert
            local _, err = openssl_x509.new(cert)
            if err then
              errors[#errors + 1] = prefix .. "ssl_cert: failed loading certificate from " .. cert
            end
          end
        end
        conf[prefix .. "ssl_cert"] = ssl_cert
      end

      if ssl_cert_key then
        for i, cert_key in ipairs(ssl_cert_key) do
          if not exists(cert_key) then
            cert_key = try_decode_base64(cert_key)
            ssl_cert_key[i] = cert_key
            local _, err = openssl_pkey.new(cert_key)
            if err then
              errors[#errors + 1] = prefix .. "ssl_cert_key: failed loading key from " .. cert_key
            end
          end
        end
        conf[prefix .. "ssl_cert_key"] = ssl_cert_key
      end
    end
  end

  if conf.client_ssl then
    local client_ssl_cert = conf.client_ssl_cert
    local client_ssl_cert_key = conf.client_ssl_cert_key

    if client_ssl_cert and not client_ssl_cert_key then
      errors[#errors + 1] = "client_ssl_cert_key must be specified"

    elseif client_ssl_cert_key and not client_ssl_cert then
      errors[#errors + 1] = "client_ssl_cert must be specified"
    end

    if client_ssl_cert and not exists(client_ssl_cert) then
      client_ssl_cert = try_decode_base64(client_ssl_cert)
      conf.client_ssl_cert = client_ssl_cert
      local _, err = openssl_x509.new(client_ssl_cert)
      if err then
        errors[#errors + 1] = "client_ssl_cert: failed loading certificate from " .. client_ssl_cert
      end
    end

    if client_ssl_cert_key and not exists(client_ssl_cert_key) then
      client_ssl_cert_key = try_decode_base64(client_ssl_cert_key)
      conf.client_ssl_cert_key = client_ssl_cert_key
      local _, err = openssl_pkey.new(client_ssl_cert_key)
      if err then
        errors[#errors + 1] = "client_ssl_cert_key: failed loading key from " ..
                               client_ssl_cert_key
      end
    end
  end

  if conf.lua_ssl_trusted_certificate then
    local new_paths = {}

    for _, trusted_cert in ipairs(conf.lua_ssl_trusted_certificate) do
      if trusted_cert == "system" then
        local system_path, err = utils.get_system_trusted_certs_filepath()
        if system_path then
          trusted_cert = system_path

        elseif not ngx.IS_CLI then
          log.info("lua_ssl_trusted_certificate: unable to locate system bundle: " .. err ..
                   ". If you are using TLS connections, consider specifying " ..
                   "\"lua_ssl_trusted_certificate\" manually")
        end
      end

      if trusted_cert ~= "system" then
        if not exists(trusted_cert) then
          trusted_cert = try_decode_base64(trusted_cert)
          local _, err = openssl_x509.new(trusted_cert)
          if err then
            errors[#errors + 1] = "lua_ssl_trusted_certificate: " ..
                                  "failed loading certificate from " ..
                                  trusted_cert
          end
        end

        new_paths[#new_paths + 1] = trusted_cert
      end
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
    if not is_predefined_dhgroup(conf.ssl_dhparam)
       and not exists(conf.ssl_dhparam) then
      conf.ssl_dhparam = try_decode_base64(conf.ssl_dhparam)
      local _, err = openssl_pkey.new(
        {
          type = "DH",
          param = conf.ssl_dhparam
        }
      )
      if err then
        errors[#errors + 1] = "ssl_dhparam: failed loading certificate from "
                              .. conf.ssl_dhparam
      end
    end

  else
    for _, key in ipairs({ "nginx_http_ssl_dhparam", "nginx_stream_ssl_dhparam" }) do
      local file = conf[key]
      if file and not is_predefined_dhgroup(file) and not exists(file) then
        errors[#errors + 1] = key .. ": no such file at " .. file
      end
    end
  end

  if conf.headers then
    for _, token in ipairs(conf.headers) do
      if token ~= "off" and not HEADER_KEY_TO_NAME[lower(token)] then
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
    local allowed = { LAST = true, A = true, AAAA = true,
                      CNAME = true, SRV = true }

    for _, name in ipairs(conf.dns_order) do
      if not allowed[upper(name)] then
        errors[#errors + 1] = fmt("dns_order: invalid entry '%s'",
                                  tostring(name))
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

  if conf.pg_max_concurrent_queries ~= floor(conf.pg_max_concurrent_queries) then
    errors[#errors + 1] = "pg_max_concurrent_queries must be an integer greater than 0"
  end

  if conf.pg_semaphore_timeout < 0 then
    errors[#errors + 1] = "pg_semaphore_timeout must be greater than 0"
  end

  if conf.pg_semaphore_timeout ~= floor(conf.pg_semaphore_timeout) then
    errors[#errors + 1] = "pg_semaphore_timeout must be an integer greater than 0"
  end

  if conf.pg_keepalive_timeout then
    if conf.pg_keepalive_timeout < 0 then
      errors[#errors + 1] = "pg_keepalive_timeout must be greater than 0"
    end

    if conf.pg_keepalive_timeout ~= floor(conf.pg_keepalive_timeout) then
      errors[#errors + 1] = "pg_keepalive_timeout must be an integer greater than 0"
    end
  end

  if conf.pg_pool_size then
    if conf.pg_pool_size < 0 then
      errors[#errors + 1] = "pg_pool_size must be greater than 0"
    end

    if conf.pg_pool_size ~= floor(conf.pg_pool_size) then
      errors[#errors + 1] = "pg_pool_size must be an integer greater than 0"
    end
  end

  if conf.pg_backlog then
    if conf.pg_backlog < 0 then
      errors[#errors + 1] = "pg_backlog must be greater than 0"
    end

    if conf.pg_backlog ~= floor(conf.pg_backlog) then
      errors[#errors + 1] = "pg_backlog must be an integer greater than 0"
    end
  end

  if conf.pg_expired_rows_cleanup_interval then
    if conf.pg_expired_rows_cleanup_interval < 0 then
      errors[#errors + 1] = "pg_expired_rows_cleanup_interval must be greater than 0"
    end

    if conf.pg_expired_rows_cleanup_interval ~= floor(conf.pg_expired_rows_cleanup_interval) then
      errors[#errors + 1] = "pg_expired_rows_cleanup_interval must be an integer greater than 0"
    end
  end

  if conf.pg_ro_max_concurrent_queries then
    if conf.pg_ro_max_concurrent_queries < 0 then
      errors[#errors + 1] = "pg_ro_max_concurrent_queries must be greater than 0"
    end

    if conf.pg_ro_max_concurrent_queries ~= floor(conf.pg_ro_max_concurrent_queries) then
      errors[#errors + 1] = "pg_ro_max_concurrent_queries must be an integer greater than 0"
    end
  end

  if conf.pg_ro_semaphore_timeout then
    if conf.pg_ro_semaphore_timeout < 0 then
      errors[#errors + 1] = "pg_ro_semaphore_timeout must be greater than 0"
    end

    if conf.pg_ro_semaphore_timeout ~= floor(conf.pg_ro_semaphore_timeout) then
      errors[#errors + 1] = "pg_ro_semaphore_timeout must be an integer greater than 0"
    end
  end

  if conf.pg_ro_keepalive_timeout then
    if conf.pg_ro_keepalive_timeout < 0 then
      errors[#errors + 1] = "pg_ro_keepalive_timeout must be greater than 0"
    end

    if conf.pg_ro_keepalive_timeout ~= floor(conf.pg_ro_keepalive_timeout) then
      errors[#errors + 1] = "pg_ro_keepalive_timeout must be an integer greater than 0"
    end
  end

  if conf.pg_ro_pool_size then
    if conf.pg_ro_pool_size < 0 then
      errors[#errors + 1] = "pg_ro_pool_size must be greater than 0"
    end

    if conf.pg_ro_pool_size ~= floor(conf.pg_ro_pool_size) then
      errors[#errors + 1] = "pg_ro_pool_size must be an integer greater than 0"
    end
  end

  if conf.pg_ro_backlog then
    if conf.pg_ro_backlog < 0 then
      errors[#errors + 1] = "pg_ro_backlog must be greater than 0"
    end

    if conf.pg_ro_backlog ~= floor(conf.pg_ro_backlog) then
      errors[#errors + 1] = "pg_ro_backlog must be an integer greater than 0"
    end
  end

  if conf.worker_state_update_frequency <= 0 then
    errors[#errors + 1] = "worker_state_update_frequency must be greater than 0"
  end

  if conf.proxy_server then
    local parsed, err = socket_url.parse(conf.proxy_server)
    if err then
      errors[#errors + 1] = "proxy_server is invalid: " .. err

    elseif not parsed.scheme then
      errors[#errors + 1] = "proxy_server missing scheme"

    elseif parsed.scheme ~= "http" and parsed.scheme ~= "https" then
      errors[#errors + 1] = "proxy_server only supports \"http\" and \"https\", got " .. parsed.scheme

    elseif not parsed.host then
      errors[#errors + 1] = "proxy_server missing host"

    elseif parsed.fragment or parsed.query or parsed.params then
      errors[#errors + 1] = "fragments, query strings or parameters are meaningless in proxy configuration"
    end
  end

  if conf.role == "control_plane" then
    if #conf.admin_listen < 1 or strip(conf.admin_listen[1]) == "off" then
      errors[#errors + 1] = "admin_listen must be specified when role = \"control_plane\""
    end

    if conf.cluster_mtls == "pki" and not conf.cluster_ca_cert then
      errors[#errors + 1] = "cluster_ca_cert must be specified when cluster_mtls = \"pki\""
    end

    if #conf.cluster_listen < 1 or strip(conf.cluster_listen[1]) == "off" then
      errors[#errors + 1] = "cluster_listen must be specified when role = \"control_plane\""
    end

    if conf.database == "off" then
      errors[#errors + 1] = "in-memory storage can not be used when role = \"control_plane\""
    end

    if conf.cluster_use_proxy then
      errors[#errors + 1] = "cluster_use_proxy can not be used when role = \"control_plane\""
    end

  elseif conf.role == "data_plane" then
    if #conf.proxy_listen < 1 or strip(conf.proxy_listen[1]) == "off" then
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
      insert(conf.lua_ssl_trusted_certificate, conf.cluster_cert)

    elseif conf.cluster_mtls == "pki" or conf.cluster_mtls == "pki_check_cn" then
      insert(conf.lua_ssl_trusted_certificate, conf.cluster_ca_cert)
    end

    if conf.cluster_use_proxy and not conf.proxy_server then
      errors[#errors + 1] = "cluster_use_proxy is turned on but no proxy_server is configured"
    end
  end

  if conf.cluster_data_plane_purge_delay < 60 then
    errors[#errors + 1] = "cluster_data_plane_purge_delay must be 60 or greater"
  end

  if conf.cluster_max_payload < 4194304 then
    errors[#errors + 1] = "cluster_max_payload must be 4194304 (4MB) or greater"
  end

  if conf.role == "control_plane" or conf.role == "data_plane" then
    local cluster_cert = conf.cluster_cert
    local cluster_cert_key = conf.cluster_cert_key
    local cluster_ca_cert = conf.cluster_ca_cert

    if not cluster_cert or not cluster_cert_key then
      errors[#errors + 1] = "cluster certificate and key must be provided to use Hybrid mode"

    else
      if not exists(cluster_cert) then
        cluster_cert = try_decode_base64(cluster_cert)
        conf.cluster_cert = cluster_cert
        local _, err = openssl_x509.new(cluster_cert)
        if err then
          errors[#errors + 1] = "cluster_cert: failed loading certificate from " .. cluster_cert
        end
      end

      if not exists(cluster_cert_key) then
        cluster_cert_key = try_decode_base64(cluster_cert_key)
        conf.cluster_cert_key = cluster_cert_key
        local _, err = openssl_pkey.new(cluster_cert_key)
        if err then
          errors[#errors + 1] = "cluster_cert_key: failed loading key from " .. cluster_cert_key
        end
      end
    end

    if cluster_ca_cert and not exists(cluster_ca_cert) then
      cluster_ca_cert = try_decode_base64(cluster_ca_cert)
      conf.cluster_ca_cert = cluster_ca_cert
      local _, err = openssl_x509.new(cluster_ca_cert)
      if err then
        errors[#errors + 1] = "cluster_ca_cert: failed loading certificate from " ..
                              cluster_ca_cert
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

  if conf.tracing_instrumentations and #conf.tracing_instrumentations > 0 then
    local instrumentation = require "kong.tracing.instrumentation"
    local available_types_map = tablex.deepcopy(instrumentation.available_types)
    available_types_map["all"] = true
    available_types_map["off"] = true
    available_types_map["request"] = true

    for _, trace_type in ipairs(conf.tracing_instrumentations) do
      if not available_types_map[trace_type] then
        errors[#errors + 1] = "invalid tracing type: " .. trace_type
      end
    end

    if #conf.tracing_instrumentations > 1
      and tablex.find(conf.tracing_instrumentations, "off")
    then
      errors[#errors + 1] = "invalid tracing types: off, other types are mutually exclusive"
    end

    if conf.tracing_sampling_rate < 0 or conf.tracing_sampling_rate > 1 then
      errors[#errors + 1] = "tracing_sampling_rate must be between 0 and 1"
    end
  end

  return #errors == 0, errors[1], errors
end


local function overrides(k, default_v, opts, file_conf, arg_conf)
  opts = opts or {}

  local value -- definitive value for this property

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

    local env_name = "KONG_" .. upper(k)
    local env = getenv(env_name)
    if env ~= nil then
      local to_print = env

      if CONF_SENSITIVE[k] then
        to_print = CONF_SENSITIVE_PLACEHOLDER
      end

      log.debug('%s ENV found with "%s"', env_name, to_print)

      value = env
    end
  end

  -- arg_conf have highest priority
  if arg_conf and arg_conf[k] ~= nil then
    value = arg_conf[k]
  end

  return value, k
end


local function parse_nginx_directives(dyn_namespace, conf, injected_in_namespace)
  conf = conf or {}
  local directives = {}

  for k, v in pairs(conf) do
    if type(k) == "string" and not injected_in_namespace[k] then
      local directive = match(k, dyn_namespace.prefix .. "(.+)")
      if directive then
        if v ~= "NONE" and not dyn_namespace.ignore[directive] then
          insert(directives, { name = directive, value = v })
        end

        injected_in_namespace[k] = true
      end
    end
  end

  return directives
end


local function aliased_properties(conf)
  for property_name, v_schema in pairs(CONF_PARSERS) do
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
  for property_name, v_schema in pairs(CONF_PARSERS) do
    local deprecated = v_schema.deprecated

    if deprecated and conf[property_name] ~= nil then
      if not opts.from_kong_env then
        if deprecated.value then
            log.warn("the configuration value '%s' for configuration property '%s' is deprecated", deprecated.value, property_name)
        end
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
  for property_name, v_schema in pairs(CONF_PARSERS) do
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


local function load_config(thing)
  local s = pl_stringio.open(thing)
  local conf, err = pl_config.read(s, {
    smart = false,
    list_delim = "_blank_" -- mandatory but we want to ignore it
  })
  s:close()
  if not conf then
    return nil, err
  end

  local function strip_comments(value)
    -- remove trailing comment, if any
    -- and remove escape chars from octothorpes
    if value then
      value = ngx.re.sub(value, [[\s*(?<!\\)#.*$]], "")
      value = gsub(value, "\\#", "#")
    end
    return value
  end

  for key, value in pairs(conf) do
    conf[key] = strip_comments(value)
  end

  return conf
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

  return load_config(f)
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
  local defaults, err = load_config(kong_default_conf)
  if not defaults then
    return nil, "could not load default conf: " .. err
  end

  ---------------------
  -- Configuration file
  ---------------------

  local from_file_conf = {}
  if path and not exists(path) then
    -- file conf has been specified and must exist
    return nil, "no file at: " .. path
  end

  if not path then
    -- try to look for a conf in default locations, but no big
    -- deal if none is found: we will use our defaults.
    for _, default_path in ipairs(DEFAULT_PATHS) do
      if exists(default_path) then
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

    from_file_conf, err = load_config_file(path)
    if not from_file_conf then
      return nil, "could not load config file: " .. err
    end
  end

  -----------------------
  -- Merging & validation
  -----------------------

  do
    -- find dynamic keys that need to be loaded
    local dynamic_keys = {}

    local function add_dynamic_keys(t)
      t = t or {}

      for property_name, v_schema in pairs(CONF_PARSERS) do
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
        local directive = match(k, "^(" .. dyn_prefix .. ".+)")
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
        local kong_var = match(lower(k), "^kong_(.+)")
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

  ---------------------------------
  -- Dereference process references
  ---------------------------------

  local loaded_vaults
  local refs
  do
    -- validation
    local vaults_array = parse_value(conf.vaults, CONF_PARSERS["vaults"].typ)

    -- merge vaults
    local vaults = {}

    if #vaults_array > 0 and vaults_array[1] ~= "off" then
      for i = 1, #vaults_array do
        local vault_name = strip(vaults_array[i])
        if vault_name ~= "off" then
          if vault_name == "bundled" then
            vaults = tablex.merge(constants.BUNDLED_VAULTS, vaults, true)

          else
            vaults[vault_name] = true
          end
        end
      end
    end

    loaded_vaults = setmetatable(vaults, _nop_tostring_mt)

    if get_phase() == "init" then
      local secrets = getenv("KONG_PROCESS_SECRETS")
      if secrets then
        C.unsetenv("KONG_PROCESS_SECRETS")

      else
        local path = pl_path.join(abspath(ngx.config.prefix()), unpack(PREFIX_PATHS.kong_process_secrets))
        if exists(path) then
          secrets, err = pl_file.read(path, true)
          pl_file.delete(path)
          if not secrets then
            return nil, fmt("failed to read process secrets file: %s", err)
          end
        end
      end

      if secrets then
        secrets, err = process_secrets.deserialize(secrets, path)
        if not secrets then
          return nil, err
        end

        for k, deref in pairs(secrets) do
          local v = parse_value(conf[k], "string")
          if refs then
            refs[k] = v
          else
            refs = setmetatable({ [k] = v }, _nop_tostring_mt)
          end

          conf[k] = deref
        end
      end

    else
      local vault_conf = { loaded_vaults = loaded_vaults }
      for k, v in pairs(conf) do
        if sub(k, 1, 6) == "vault_" then
          vault_conf[k] = parse_value(v, "string")
        end
      end

      local vault = require("kong.pdk.vault").new({ configuration = vault_conf })

      for k, v in pairs(conf) do
        v = parse_value(v, "string")
        if vault.is_reference(v) then
          if refs then
            refs[k] = v
          else
            refs = setmetatable({ [k] = v }, _nop_tostring_mt)
          end

          local deref, deref_err = vault.get(v)
          if deref == nil or deref_err then
            return nil, fmt("failed to dereference '%s': %s for config option '%s'", v, deref_err, k)
          end

          if deref ~= nil then
            conf[k] = deref
          end
        end
      end
    end
  end

  -- validation
  local ok, err, errors = check_and_parse(conf, opts)

  if not opts.starting then
    log.enable()
  end

  if not ok then
    return nil, err, errors
  end

  conf = tablex.merge(conf, defaults) -- intersection (remove extraneous properties)

  conf.loaded_vaults = loaded_vaults
  conf["$refs"] = refs

  local default_nginx_main_user = false
  local default_nginx_user = false

  do
    -- nginx 'user' directive
    local user = gsub(strip(conf.nginx_main_user), "%s+", " ")
    if user == "nobody" or user == "nobody nobody" then
      conf.nginx_main_user = nil

    elseif user == "kong" or user == "kong kong" then
      default_nginx_main_user = true
    end

    local user = gsub(strip(conf.nginx_user), "%s+", " ")
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

    sort(conf_arr)

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
        local plugin_name = strip(conf.plugins[i])
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
         and find(directive.value, "prometheus_metrics", nil, true)
      then
         found = true
         break
      end
    end

    if not found then
      insert(http_directives, {
        name  = "lua_shared_dict",
        value = "prometheus_metrics 5m",
      })
    end

    local stream_directives = conf["nginx_stream_directives"]
    local found = false

    for _, directive in pairs(stream_directives) do
      if directive.name == "lua_shared_dict"
        and find(directive.value, "stream_prometheus_metrics", nil, true)
      then
        found = true
        break
      end
    end

    if not found then
      insert(stream_directives, {
        name  = "lua_shared_dict",
        value = "stream_prometheus_metrics 5m",
      })
    end
  end

  for _, dyn_namespace in ipairs(DYNAMIC_KEY_NAMESPACES) do
    if dyn_namespace.injected_conf_name then
      sort(conf[dyn_namespace.injected_conf_name], function(a, b)
        return a.name < b.name
      end)
    end
  end

  ok, err = listeners.parse(conf, {
    { name = "proxy_listen",   subsystem = "http",   ssl_flag = "proxy_ssl_enabled" },
    { name = "stream_listen",  subsystem = "stream", ssl_flag = "stream_proxy_ssl_enabled" },
    { name = "admin_listen",   subsystem = "http",   ssl_flag = "admin_ssl_enabled" },
    { name = "status_listen",  subsystem = "http",   ssl_flag = "status_ssl_enabled" },
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
          enabled_headers[HEADER_KEY_TO_NAME[lower(token)]] = true
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
  conf.prefix = abspath(conf.prefix)

  for _, prefix in ipairs({ "ssl", "admin_ssl", "status_ssl", "client_ssl", "cluster" }) do
    local ssl_cert = conf[prefix .. "_cert"]
    local ssl_cert_key = conf[prefix .. "_cert_key"]

    if ssl_cert and ssl_cert_key then
      if type(ssl_cert) == "table" then
        for i, cert in ipairs(ssl_cert) do
          if exists(ssl_cert[i]) then
            ssl_cert[i] = abspath(cert)
          end
        end

      elseif exists(ssl_cert) then
        conf[prefix .. "_cert"] = abspath(ssl_cert)
      end

      if type(ssl_cert_key) == "table" then
        for i, key in ipairs(ssl_cert_key) do
          if exists(ssl_cert_key[i]) then
            ssl_cert_key[i] = abspath(key)
          end
        end

      elseif exists(ssl_cert_key) then
        conf[prefix .. "_cert_key"] = abspath(ssl_cert_key)
      end
    end
  end

  if conf.cluster_ca_cert and exists(conf.cluster_ca_cert) then
    conf.cluster_ca_cert = abspath(conf.cluster_ca_cert)
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
            directive.value = abspath(pl_path.join(conf.prefix, "ssl", directive.value .. ".pem"))

          else
            remove(conf[name], i)
          end

        elseif exists(directive.value) then
          directive.value = abspath(directive.value)
        end

        break
      end
    end
  end

  if conf.lua_ssl_trusted_certificate
     and #conf.lua_ssl_trusted_certificate > 0 then

    conf.lua_ssl_trusted_certificate = tablex.map(
      function(cert)
        if exists(cert) then
          return abspath(cert)
        end
        return cert
      end,
      conf.lua_ssl_trusted_certificate
    )

    conf.lua_ssl_trusted_certificate_combined =
      abspath(pl_path.join(conf.prefix, ".ca_combined"))
  end

  -- attach prefix files paths
  for property, t_path in pairs(PREFIX_PATHS) do
    conf[property] = pl_path.join(conf.prefix, unpack(t_path))
  end

  log.verbose("prefix in use: %s", conf.prefix)

  -- hybrid mode HTTP tunneling (CONNECT) proxy inside HTTPS
  if conf.cluster_use_proxy then
    -- throw err, assume it's already handled in check_and_parse
    local parsed = assert(socket_url.parse(conf.proxy_server))
    if parsed.scheme == "https" then
      conf.cluster_ssl_tunnel = fmt("%s:%s", parsed.host, parsed.port or 443)
    end
  end

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

    local refs = purged_conf["$refs"]
    if type(refs) == "table" then
      for k, v in pairs(refs) do
        if not CONF_SENSITIVE[k] then
          purged_conf[k] = v
        end
      end
      purged_conf["$refs"] = nil
    end

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
