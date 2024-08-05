local require = require


local pl_path = require "pl.path"
local socket_url = require "socket.url"
local tablex = require "pl.tablex"
local openssl_x509 = require "resty.openssl.x509"
local openssl_pkey = require "resty.openssl.pkey"
local log = require "kong.cmd.utils.log"
local nginx_signals = require "kong.cmd.utils.nginx_signals"
local conf_constants = require "kong.conf_loader.constants"
local tools_system = require "kong.tools.system" -- for unit-testing
local tools_ip = require "kong.tools.ip"
local tools_string = require "kong.tools.string"


local normalize_ip = tools_ip.normalize_ip
local is_valid_ip_or_cidr = tools_ip.is_valid_ip_or_cidr
local try_decode_base64 = tools_string.try_decode_base64
local strip = tools_string.strip
local split = tools_string.split
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy
local is_valid_uuid = require("kong.tools.uuid").is_valid_uuid


local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local tonumber = tonumber
local setmetatable = setmetatable
local floor = math.floor
local fmt = string.format
local find = string.find
local sub = string.sub
local lower = string.lower
local upper = string.upper
local match = string.match
local insert = table.insert
local concat = table.concat
local getenv = os.getenv
local re_match = ngx.re.match
local exists = pl_path.exists
local isdir = pl_path.isdir


local get_phase do
  if ngx and ngx.get_phase then
    get_phase = ngx.get_phase
  else
    get_phase = function()
      return "timer"
    end
  end
end


local function is_predefined_dhgroup(group)
  if type(group) ~= "string" then
    return false
  end

  return not not openssl_pkey.paramgen({
    type = "DH",
    group = group,
  })
end


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
    value = setmetatable(split(value, ","), nil) -- remove List mt

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


-- Check if module is dynamic
local function check_dynamic_module(mod_name)
  local configure_line = ngx.config.nginx_configure()
  local mod_re = [[^.*--add-dynamic-module=(.+\/]] .. mod_name .. [[(\s|$)).*$]]
  return re_match(configure_line, mod_re, "oi") ~= nil
end


-- Lookup dynamic module object
-- this function will lookup for the `mod_name` dynamic module in the following
-- paths:
--  - /usr/local/kong/modules -- default path for modules in container images
--  - <nginx binary path>/../modules
-- @param[type=string] mod_name The module name to lookup, without file extension
local function lookup_dynamic_module_so(mod_name, kong_conf)
  log.debug("looking up dynamic module %s", mod_name)

  local mod_file = fmt("/usr/local/kong/modules/%s.so", mod_name)
  if exists(mod_file) then
    log.debug("module '%s' found at '%s'", mod_name, mod_file)
    return mod_file
  end

  local nginx_bin = nginx_signals.find_nginx_bin(kong_conf)
  mod_file = fmt("%s/../modules/%s.so", pl_path.dirname(nginx_bin), mod_name)
  if exists(mod_file) then
    log.debug("module '%s' found at '%s'", mod_name, mod_file)
    return mod_file
  end

  return nil, fmt("%s dynamic module shared object not found", mod_name)
end


-- Validate Wasm properties
local function validate_wasm(conf)
  local wasm_enabled = conf.wasm
  local filters_path = conf.wasm_filters_path

  if wasm_enabled then
    if filters_path and not exists(filters_path) and not isdir(filters_path) then
      return nil, fmt("wasm_filters_path '%s' is not a valid directory", filters_path)
    end
  end

  return true
end


local validate_labels
do
  local MAX_KEY_SIZE   = 63
  local MAX_VALUE_SIZE = 63
  local MAX_KEYS_COUNT = 10


  -- validation rules based on Kong Labels AIP
  -- https://kong-aip.netlify.app/aip/129/
  local BASE_PTRN = "[a-z0-9]([\\w\\.:-]*[a-z0-9]|)$"
  local KEY_PTRN  = "(?!kong)(?!konnect)(?!insomnia)(?!mesh)(?!kic)" .. BASE_PTRN
  local VAL_PTRN  = BASE_PTRN


  local function validate_entry(str, max_size, pattern)
    if str == "" or #str > max_size then
      return nil, fmt(
        "%s must have between 1 and %d characters", str, max_size)
    end
    if not re_match(str, pattern, "ajoi") then
      return nil, fmt("%s is invalid. Must match pattern: %s", str, pattern)
    end
    return true
  end


  -- Validates a label array.
  -- Validates labels based on the kong Labels AIP
  function validate_labels(raw_labels)
    local nkeys = require "table.nkeys"
    if nkeys(raw_labels) > MAX_KEYS_COUNT then
      return nil, fmt(
        "labels validation failed: count exceeded %d max elements",
        MAX_KEYS_COUNT
      )
    end

    for _, kv in ipairs(raw_labels) do
      local del = kv:find(":", 1, true)
      local k = del and kv:sub(1, del - 1) or ""
      local v = del and kv:sub(del + 1) or ""

      local ok, err = validate_entry(k, MAX_KEY_SIZE, KEY_PTRN)
      if not ok then
        return nil, "label key validation failed: " .. err
      end
      ok, err = validate_entry(v, MAX_VALUE_SIZE, VAL_PTRN)
      if not ok then
        return nil, "label value validation failed: " .. err
      end
    end

    return true
  end
end


-- Validate properties (type/enum/custom) and infer their type.
-- @param[type=table] conf The configuration table to treat.
local function check_and_parse(conf, opts)
  local errors = {}

  for k, value in pairs(conf) do
    local v_schema = conf_constants.CONF_PARSERS[k] or {}

    value = parse_value(value, v_schema.typ)

    local typ = v_schema.typ or "string"
    if value and not conf_constants.TYP_CHECKS[typ](value) then
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

  if conf.lua_ssl_trusted_certificate then
    local new_paths = {}

    for _, trusted_cert in ipairs(conf.lua_ssl_trusted_certificate) do
      if trusted_cert == "system" then
        local system_path, err = tools_system.get_system_trusted_certs_filepath()
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

  -- leave early if we're still at the stage before executing the main `resty` cmd
  if opts.pre_cmd then
    return #errors == 0, errors[1], errors
  end

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

  for _, prefix in ipairs({ "proxy_", "admin_", "admin_gui_", "status_" }) do
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

  if conf.admin_gui_path then
    if not conf.admin_gui_path:find("^/") then
      errors[#errors + 1] = "admin_gui_path must start with a slash ('/')"
    end
    if conf.admin_gui_path:find("^/.+/$") then
        errors[#errors + 1] = "admin_gui_path must not end with a slash ('/')"
    end
    if conf.admin_gui_path:match("[^%a%d%-_/]+") then
      errors[#errors + 1] = "admin_gui_path can only contain letters, digits, " ..
        "hyphens ('-'), underscores ('_'), and slashes ('/')"
    end
    if conf.admin_gui_path:match("//+") then
      errors[#errors + 1] = "admin_gui_path must not contain continuous slashes ('/')"
    end
  end

  if conf.ssl_cipher_suite ~= "custom" then
    local suite = conf_constants.CIPHER_SUITES[conf.ssl_cipher_suite]
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

      else
        for _, key in ipairs({
          "nginx_http_ssl_conf_command",
          "nginx_http_proxy_ssl_conf_command",
          "nginx_http_lua_ssl_conf_command",
          "nginx_http_grpc_ssl_conf_command",
          "nginx_stream_ssl_conf_command",
          "nginx_stream_proxy_ssl_conf_command",
          "nginx_stream_lua_ssl_conf_command"}) do

          if conf[key] then
            local _, _, seclevel = find(conf[key], "@SECLEVEL=(%d+)")
            if seclevel ~= "0" then
              ngx.log(ngx.WARN, key, ": Default @SECLEVEL=0 overridden, TLSv1.1 unavailable")
            end
          end
        end
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
      if token ~= "off" and not conf_constants.HEADER_KEY_TO_NAME[lower(token)] then
        errors[#errors + 1] = fmt("headers: invalid entry '%s'",
                                  tostring(token))
      end
    end
  end

  if conf.headers_upstream then
    for _, token in ipairs(conf.headers_upstream) do
      if token ~= "off" and not conf_constants.UPSTREAM_HEADER_KEY_TO_NAME[lower(token)] then
        errors[#errors + 1] = fmt("headers_upstream: invalid entry '%s'",
                                  tostring(token))
      end
    end
  end

  if conf.dns_resolver then
    for _, server in ipairs(conf.dns_resolver) do
      local dns = normalize_ip(server)

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

  --- new dns client

  if conf.resolver_address then
    for _, server in ipairs(conf.resolver_address) do
      local dns = normalize_ip(server)

      if not dns or dns.type == "name" then
        errors[#errors + 1] = "resolver_address must be a comma separated list " ..
                              "in the form of IPv4/6 or IPv4/6:port, got '"  ..
                              server .. "'"
      end
    end
  end

  if conf.resolver_hosts_file then
    if not pl_path.isfile(conf.resolver_hosts_file) then
      errors[#errors + 1] = "resolver_hosts_file: file does not exist"
    end
  end

  if conf.resolver_family then
    local allowed = { A = true, AAAA = true, SRV = true }

    for _, name in ipairs(conf.resolver_family) do
      if not allowed[upper(name)] then
        errors[#errors + 1] = fmt("resolver_family: invalid entry '%s'",
                                  tostring(name))
      end
    end
  end

  if not conf.lua_package_cpath then
    conf.lua_package_cpath = ""
  end

  -- checking the trusted ips
  for _, address in ipairs(conf.trusted_ips) do
    if not is_valid_ip_or_cidr(address) and address ~= "unix:" then
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

    if conf.cluster_dp_labels and #conf.cluster_dp_labels > 0 then
      errors[#errors + 1] = "cluster_dp_labels can not be used when role = \"control_plane\""
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

    if conf.cluster_dp_labels then
      local _, err = validate_labels(conf.cluster_dp_labels)
      if err then
       errors[#errors + 1] = err
      end
    end

  else
    if conf.cluster_dp_labels and #conf.cluster_dp_labels > 0 then
      errors[#errors + 1] = "cluster_dp_labels can only be used when role = \"data_plane\""
    end
  end

  if conf.cluster_data_plane_purge_delay < 60 then
    errors[#errors + 1] = "cluster_data_plane_purge_delay must be 60 or greater"
  end

  if conf.cluster_max_payload < 4194304 then
    errors[#errors + 1] = "cluster_max_payload must be 4194304 (4MB) or greater"
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
    local instrumentation = require "kong.observability.tracing.instrumentation"
    local available_types_map = cycle_aware_deep_copy(instrumentation.available_types)
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

  if conf.lua_max_req_headers < 1 or conf.lua_max_req_headers > 1000
  or conf.lua_max_req_headers ~= floor(conf.lua_max_req_headers)
  then
    errors[#errors + 1] = "lua_max_req_headers must be an integer between 1 and 1000"
  end

  if conf.lua_max_resp_headers < 1 or conf.lua_max_resp_headers > 1000
  or conf.lua_max_resp_headers ~= floor(conf.lua_max_resp_headers)
  then
    errors[#errors + 1] = "lua_max_resp_headers must be an integer between 1 and 1000"
  end

  if conf.lua_max_uri_args < 1 or conf.lua_max_uri_args > 1000
  or conf.lua_max_uri_args ~= floor(conf.lua_max_uri_args)
  then
    errors[#errors + 1] = "lua_max_uri_args must be an integer between 1 and 1000"
  end

  if conf.lua_max_post_args < 1 or conf.lua_max_post_args > 1000
  or conf.lua_max_post_args ~= floor(conf.lua_max_post_args)
  then
    errors[#errors + 1] = "lua_max_post_args must be an integer between 1 and 1000"
  end

  if conf.node_id and not is_valid_uuid(conf.node_id) then
    errors[#errors + 1] = "node_id must be a valid UUID"
  end

  if conf.database == "cassandra" then
    errors[#errors + 1] = "Cassandra as a datastore for Kong is not supported in versions 3.4 and above. Please use Postgres."
  end

  local ok, err = validate_wasm(conf)
  if not ok then
    errors[#errors + 1] = err
  end

  if conf.wasm and check_dynamic_module("ngx_wasmx_module") then
    local err
    conf.wasm_dynamic_module, err = lookup_dynamic_module_so("ngx_wasmx_module", conf)
    if err then
      errors[#errors + 1] = err
    end
  end

  if #conf.admin_listen < 1 or strip(conf.admin_listen[1]) == "off" then
    if #conf.admin_gui_listen > 0 and strip(conf.admin_gui_listen[1]) ~= "off" then
      log.warn("Kong Manager won't be functional because the Admin API is not listened on any interface")
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

      if conf_constants.CONF_SENSITIVE[k] then
        to_print = conf_constants.CONF_SENSITIVE_PLACEHOLDER
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


return {
  get_phase = get_phase,

  is_predefined_dhgroup = is_predefined_dhgroup,
  parse_value = parse_value,

  check_and_parse = check_and_parse,

  overrides = overrides,
  parse_nginx_directives = parse_nginx_directives,
}
