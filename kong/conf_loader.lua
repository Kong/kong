local kong_default_conf = require "kong.templates.kong_defaults"
local pl_stringio = require "pl.stringio"
local pl_stringx = require "pl.stringx"
local constants = require "kong.constants"
local pl_pretty = require "pl.pretty"
local pl_config = require "pl.config"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local tablex = require "pl.tablex"
local utils = require "kong.tools.utils"
local log = require "kong.cmd.utils.log"
local env = require "kong.cmd.utils.env"
local ip = require "resty.mediador.ip"


local fmt = string.format
local concat = table.concat


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

  ssl_cert_default = {"ssl", "kong-default.crt"},
  ssl_cert_key_default = {"ssl", "kong-default.key"},
  ssl_cert_csr_default = {"ssl", "kong-default.csr"},

  client_ssl_cert_default = {"ssl", "kong-default.crt"},
  client_ssl_cert_key_default = {"ssl", "kong-default.key"},

  admin_ssl_cert_default = {"ssl", "admin-kong-default.crt"},
  admin_ssl_cert_key_default = {"ssl", "admin-kong-default.key"},

  status_ssl_cert_default = {"ssl", "status-kong-default.crt"},
  status_ssl_cert_key_default = {"ssl", "status-kong-default.key"},
}


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
  proxy_listen = { typ = "array" },
  admin_listen = { typ = "array" },
  status_listen = { typ = "array" },
  stream_listen = { typ = "array" },
  cluster_listen = { typ = "array" },
  db_update_frequency = {  typ = "number"  },
  db_update_propagation = {  typ = "number"  },
  db_cache_ttl = {  typ = "number"  },
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
  upstream_keepalive = { -- TODO: remove since deprecated in 1.3
    typ = "number",
    deprecated = {
      replacement = "nginx_upstream_keepalive",
      alias = function(conf)
        if tonumber(conf.upstream_keepalive) == 0 then
          conf.nginx_upstream_keepalive = "NONE"

        elseif conf.nginx_upstream_keepalive == nil then
          conf.nginx_upstream_keepalive = tostring(conf.upstream_keepalive)
        end
      end,
    }
  },
  nginx_http_upstream_keepalive = { -- TODO: remove since deprecated in 2.0
    typ = "string",
    deprecated = {
      replacement = "nginx_upstream_keepalive",
      alias = function(conf)
        if conf.nginx_upstream_keepalive == nil then
          conf.nginx_upstream_keepalive = tostring(conf.nginx_http_upstream_keepalive)
        end
      end,
    }
  },
  nginx_http_upstream_keepalive_timeout = { -- TODO: remove since deprecated in 2.0
    typ = "string",
    deprecated = {
      replacement = "nginx_upstream_keepalive_timeout",
      alias = function(conf)
        if conf.nginx_upstream_keepalive_timeout == nil then
          conf.nginx_upstream_keepalive_timeout = tostring(conf.nginx_http_upstream_keepalive_timeout)
        end
      end,
    }
  },
  nginx_http_upstream_keepalive_requests = { -- TODO: remove since deprecated in 2.0
    typ = "string",
    deprecated = {
      replacement = "nginx_upstream_keepalive_requests",
      alias = function(conf)
        if conf.nginx_upstream_keepalive_requests == nil then
          conf.nginx_upstream_keepalive_requests = tostring(conf.nginx_http_upstream_keepalive_requests)
        end
      end,
    }
  },
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
    alias = {
      replacement = "nginx_http_client_max_body_size",
    }
  },
  client_body_buffer_size = {
    typ = "string",
    alias = {
      replacement = "nginx_http_client_body_buffer_size",
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

  cassandra_contact_points = { typ = "array" },
  cassandra_port = { typ = "number" },
  cassandra_password = { typ = "string" },
  cassandra_timeout = { typ = "number" },
  cassandra_ssl = { typ = "boolean" },
  cassandra_ssl_verify = { typ = "boolean" },
  cassandra_consistency = { enum = {
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
  dns_not_found_ttl = { typ = "number" },
  dns_error_ttl = { typ = "number" },
  dns_no_sync = { typ = "boolean" },

  router_consistency = { enum = { "strict", "eventual" } },
  router_update_frequency = { typ = "number" },

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

  lua_ssl_verify_depth = { typ = "number" },
  lua_socket_pool_size = { typ = "number" },

  role = { enum = { "data_plane", "control_plane", "traditional", }, },
  cluster_control_plane = { typ = "string", },
  cluster_cert = { typ = "string" },
  cluster_cert_key = { typ = "string" },
}


-- List of settings whose values must not be printed when
-- using the CLI in debug mode (which prints all settings).
local CONF_SENSITIVE_PLACEHOLDER = "******"
local CONF_SENSITIVE = {
  pg_password = true,
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
local function check_and_infer(conf)
  local errors = {}

  for k, value in pairs(conf) do
    local v_schema = CONF_INFERENCES[k] or {}
    local typ = v_schema.typ

    if type(value) == "string" then
      -- remove trailing comment, if any
      -- and remove escape chars from octothorpes
      value = string.gsub(value, "[^\\]#.-$", "")
      value = string.gsub(value, "\\#", "#")

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

  if (concat(conf.proxy_listen, ",") .. " "):find("%sssl[%s,]") then
    if conf.ssl_cert and not conf.ssl_cert_key then
      errors[#errors + 1] = "ssl_cert_key must be specified"

    elseif conf.ssl_cert_key and not conf.ssl_cert then
      errors[#errors + 1] = "ssl_cert must be specified"
    end

    if conf.ssl_cert and not pl_path.exists(conf.ssl_cert) then
      errors[#errors + 1] = "ssl_cert: no such file at " .. conf.ssl_cert
    end

    if conf.ssl_cert_key and not pl_path.exists(conf.ssl_cert_key) then
      errors[#errors + 1] = "ssl_cert_key: no such file at " .. conf.ssl_cert_key
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

  if (concat(conf.admin_listen, ",") .. " "):find("%sssl[%s,]") then
    if conf.admin_ssl_cert and not conf.admin_ssl_cert_key then
      errors[#errors + 1] = "admin_ssl_cert_key must be specified"

    elseif conf.admin_ssl_cert_key and not conf.admin_ssl_cert then
      errors[#errors + 1] = "admin_ssl_cert must be specified"
    end

    if conf.admin_ssl_cert and not pl_path.exists(conf.admin_ssl_cert) then
      errors[#errors + 1] = "admin_ssl_cert: no such file at " ..
                          conf.admin_ssl_cert
    end

    if conf.admin_ssl_cert_key and not pl_path.exists(conf.admin_ssl_cert_key) then
      errors[#errors + 1] = "admin_ssl_cert_key: no such file at " ..
                          conf.admin_ssl_cert_key
    end
  end

  if conf.lua_ssl_trusted_certificate and
     not pl_path.exists(conf.lua_ssl_trusted_certificate)
  then
    errors[#errors + 1] = "lua_ssl_trusted_certificate: no such file at " ..
                        conf.lua_ssl_trusted_certificate
  end

  if conf.ssl_cipher_suite ~= "custom" then
    local suite = cipher_suites[conf.ssl_cipher_suite]
    if suite then
      conf.ssl_ciphers = suite.ciphers
      conf.nginx_http_ssl_protocols = suite.protocols
      conf.nginx_http_ssl_prefer_server_ciphers = suite.prefer_server_ciphers
      conf.nginx_stream_ssl_protocols = suite.protocols
      conf.nginx_stream_ssl_prefer_server_ciphers = suite.prefer_server_ciphers

    else
      errors[#errors + 1] = "Undefined cipher suite " .. tostring(conf.ssl_cipher_suite)
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
    local allowed = { LAST = true, A = true, CNAME = true, SRV = true }

    for _, name in ipairs(conf.dns_order) do
      if not allowed[name:upper()] then
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
    if not ip.valid(address) and address ~= "unix:" then
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

  if conf.router_update_frequency <= 0 then
    errors[#errors + 1] = "router_update_frequency must be greater than 0"
  end

  if conf.role == "control_plane" then
    if #conf.admin_listen < 1 or pl_stringx.strip(conf.admin_listen[1]) == "off" then
      errors[#errors + 1] = "admin_listen must be specified when role = \"control_plane\""
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


-- @param value The options string to check for flags (whitespace separated)
-- @param flags List of boolean flags to check for.
-- @returns 1) remainder string after all flags removed, 2) table with flag
-- booleans, 3) sanitized flags string
local function parse_option_flags(value, flags)
  assert(type(value) == "string")

  value = " " .. value .. " "

  local sanitized = ""
  local result = {}

  for _, flag in ipairs(flags) do
    local count
    local patt = "%s(" .. flag .. ")%s"

    local found = value:match(patt)
    if found then
      -- replace pattern like `backlog=%d+` with actual values
      flag = found
    end

    value, count = value:gsub(patt, " ")

    if count > 0 then
      result[flag] = true
      sanitized = sanitized .. " " .. flag

    else
      result[flag] = false
    end
  end

  return pl_stringx.strip(value), result, pl_stringx.strip(sanitized)
end


-- Parses a listener address line.
-- Supports multiple (comma separated) addresses, with flags such as
-- 'ssl' and 'http2' added to the end.
-- Pre- and postfixed whitespace as well as comma's are allowed.
-- "off" as a first entry will return empty tables.
-- @param values list of entries (strings)
-- @param flags array of strings listing accepted flags.
-- @return list of parsed entries, each entry having fields
-- `listener` (string, full listener), `ip` (normalized string)
-- `port` (number), and a boolean entry for each flag added to the entry
-- (e.g. `ssl`).
local function parse_listeners(values, flags)
  assert(type(flags) == "table")
  local list = {}
  local usage = "must be of form: [off] | <ip>:<port> [" ..
                concat(flags, "] [") .. "], [... next entry ...]"

  if #values == 0 then
    return nil, usage
  end

  if pl_stringx.strip(values[1]) == "off" then
    return list
  end

  for _, entry in ipairs(values) do
    -- parse the flags
    local remainder, listener, cleaned_flags = parse_option_flags(entry, flags)

    -- verify IP for remainder
    local ip

    if utils.hostname_type(remainder) == "name" then
      -- it's not an IP address, so a name/wildcard/regex
      ip = {}
      ip.host, ip.port = remainder:match("(.+):([%d]+)$")

    else
      -- It's an IPv4 or IPv6, normalize it
      ip = utils.normalize_ip(remainder)
      -- nginx requires brackets in IPv6 addresses, but normalize_ip does
      -- not include them (due to backwards compatibility with its other uses)
      if ip and ip.type == "ipv6" then
        ip.host = "[" .. ip.host .. "]"
      end
    end

    if not ip or not ip.port then
      return nil, usage
    end

    listener.ip = ip.host
    listener.port = ip.port
    listener.listener = ip.host .. ":" .. ip.port ..
                        (#cleaned_flags == 0 and "" or " " .. cleaned_flags)

    table.insert(list, listener)
  end

  return list
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
        local directive = string.match(k, "(" .. dyn_prefix .. ".+)")
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
                                   { no_defaults = true },
                                   from_file_conf, custom_conf)

  if not opts.starting then
    log.disable()
  end

  aliased_properties(user_conf)
  dynamic_properties(user_conf)
  deprecated_properties(user_conf, opts)

  -- merge user_conf with defaults
  local conf = tablex.pairmap(overrides, defaults,
                              { defaults_only = true },
                              user_conf)

  -- validation
  local ok, err, errors = check_and_infer(conf)

  if not opts.starting then
    log.enable()
  end

  if not ok then
    return nil, err, errors
  end

  conf = tablex.merge(conf, defaults) -- intersection (remove extraneous properties)

  do
    -- nginx 'user' directive
    local user = utils.strip(conf.nginx_main_user):gsub("%s+", " ")
    if user == "nobody" or user == "nobody nobody" then
      conf.nginx_main_user = nil
    end

    local user = utils.strip(conf.nginx_user):gsub("%s+", " ")
    if user == "nobody" or user == "nobody nobody" then
      conf.nginx_user = nil
    end
  end

  do
    local injected_in_namespace = {}

    -- nginx directives from conf
    for _, dyn_namespace in ipairs(DYNAMIC_KEY_NAMESPACES) do
      injected_in_namespace[dyn_namespace.injected_conf_name] = true

      local directives = parse_nginx_directives(dyn_namespace, conf,
                                                injected_in_namespace)
      conf[dyn_namespace.injected_conf_name] = setmetatable(directives,
                                                            _nop_tostring_mt)
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

  do
    local sub  = string.sub
    local byte = string.byte
    local find = string.find

    local COMMA        = byte(",")
    local SINGLE_QUOTE = byte("'")
    local DOUBLE_QUOTE = byte('"')
    local BACKSLASH    = byte("\\")

    for _, dyn_namespace in ipairs(DYNAMIC_KEY_NAMESPACES) do
      local directives = conf[dyn_namespace.injected_conf_name]
      local directive_count = #directives
      for i = 1, directive_count do
        local directive = directives[i]
        local value = directive.value
        if find(value, ",", 1, true) then
          local escaped = false
          local single_quoted = false
          local double_quoted = false
          local length = #value
          local start_position = 1
          local is_first = true
          for j = 1, length do
            local b = byte(value, j)
            if b == BACKSLASH then
              escaped = not escaped

            else
              if not escaped then
                if b == SINGLE_QUOTE then
                  single_quoted = not single_quoted

                elseif b == DOUBLE_QUOTE then
                  double_quoted = not double_quoted

                elseif b == COMMA and not single_quoted and not double_quoted then
                  local v = utils.strip(sub(value, start_position, j - 1))
                  if is_first then
                    directive.value = v
                    is_first = false

                  else
                    table.insert(directives, {
                      name  = directive.name,
                      value = v,
                    })
                  end

                  start_position = j + 1
                end
              end

              escaped = false
            end
          end

          if not is_first and start_position <= length then
            local v = utils.strip(sub(value, start_position))
            table.insert(directives, {
              name  = directive.name,
              value = v,
            })
          end
        end
      end

      table.sort(directives, function(a, b)
        if a.name < b.name then
          return true
        elseif a.name > b.name then
          return false
        end

        if a.value < b.value then
          return true
        end

        return false
      end)
    end
  end

  do
    local http_flags = { "ssl", "http2", "proxy_protocol", "deferred",
                         "bind", "reuseport", "backlog=%d+" }
    local stream_flags = { "ssl", "proxy_protocol", "bind", "reuseport",
                           "backlog=%d+" }

    -- extract ports/listen ips
    conf.proxy_listeners, err = parse_listeners(conf.proxy_listen, http_flags)
    if err then
      return nil, "proxy_listen " .. err
    end
    setmetatable(conf.proxy_listeners, _nop_tostring_mt)

    conf.proxy_ssl_enabled = false
    for _, listener in ipairs(conf.proxy_listeners) do
      if listener.ssl == true then
        conf.proxy_ssl_enabled = true
        break
      end
    end

    conf.stream_listeners, err = parse_listeners(conf.stream_listen, stream_flags)
    if err then
      return nil, "stream_listen " .. err
    end
    setmetatable(conf.stream_listeners, _nop_tostring_mt)

    conf.stream_proxy_ssl_enabled = false
    for _, listener in ipairs(conf.stream_listeners) do
      if listener.ssl == true then
        conf.stream_proxy_ssl_enabled = true
        break
      end
    end

    conf.admin_listeners, err = parse_listeners(conf.admin_listen, http_flags)
    if err then
      return nil, "admin_listen " .. err
    end
    setmetatable(conf.admin_listeners, _nop_tostring_mt)

    conf.admin_ssl_enabled = false
    for _, listener in ipairs(conf.admin_listeners) do
      if listener.ssl == true then
        conf.admin_ssl_enabled = true
        break
      end
    end

    conf.status_listeners, err = parse_listeners(conf.status_listen, { "ssl" })
    if err then
      return nil, "status_listen " .. err
    end
    setmetatable(conf.status_listeners, _nop_tostring_mt)

    conf.status_ssl_enabled = false
    for _, listener in ipairs(conf.status_listeners) do
      if listener.ssl == true then
        conf.status_ssl_enabled = true
        break
      end
    end

    conf.cluster_listeners, err = parse_listeners(conf.cluster_listen, http_flags)
    if err then
      return nil, "cluster_listen " .. err
    end
    setmetatable(conf.cluster_listeners, _nop_tostring_mt)
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

  conf.go_pluginserver_exe = pl_path.abspath(conf.go_pluginserver_exe)

  if conf.go_plugins_dir ~= "off" then
    conf.go_plugins_dir = pl_path.abspath(conf.go_plugins_dir)
  end

  if conf.ssl_cert and conf.ssl_cert_key then
    conf.ssl_cert = pl_path.abspath(conf.ssl_cert)
    conf.ssl_cert_key = pl_path.abspath(conf.ssl_cert_key)
  end

  if conf.client_ssl_cert and conf.client_ssl_cert_key then
    conf.client_ssl_cert = pl_path.abspath(conf.client_ssl_cert)
    conf.client_ssl_cert_key = pl_path.abspath(conf.client_ssl_cert_key)
  end

  if conf.admin_ssl_cert and conf.admin_ssl_cert_key then
    conf.admin_ssl_cert = pl_path.abspath(conf.admin_ssl_cert)
    conf.admin_ssl_cert_key = pl_path.abspath(conf.admin_ssl_cert_key)
  end

  if conf.lua_ssl_trusted_certificate then
    conf.lua_ssl_trusted_certificate =
      pl_path.abspath(conf.lua_ssl_trusted_certificate)
  end

  if conf.cluster_cert and conf.cluster_cert_key then
    conf.cluster_cert = pl_path.abspath(conf.cluster_cert)
    conf.cluster_cert_key = pl_path.abspath(conf.cluster_cert_key)
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
