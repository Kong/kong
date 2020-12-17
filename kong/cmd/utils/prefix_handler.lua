local default_nginx_template = require "kong.templates.nginx"
local kong_nginx_template = require "kong.templates.nginx_kong"
local kong_nginx_stream_template = require "kong.templates.nginx_kong_stream"
local system_constants = require "lua_system_constants"
local openssl_bignum = require "resty.openssl.bn"
local openssl_rand = require "resty.openssl.rand"
local openssl_pkey = require "resty.openssl.pkey"
local x509 = require "resty.openssl.x509"
local x509_extension = require "resty.openssl.x509.extension"
local x509_name = require "resty.openssl.x509.name"
local pl_template = require "pl.template"
local pl_stringx = require "pl.stringx"
local pl_tablex = require "pl.tablex"
local pl_utils = require "pl.utils"
local pl_file = require "pl.file"
local pl_path = require "pl.path"
local pl_dir = require "pl.dir"
local log = require "kong.cmd.utils.log"
local ffi = require "ffi"
local bit = require "bit"
local nginx_signals = require "kong.cmd.utils.nginx_signals"


local tonumber = tonumber
local tostring = tostring
local assert = assert
local string = string
local ipairs = ipairs
local pairs = pairs
local table = table
local type = type
local math = math
local io = io
local os = os


local function pre_create_private_file(file)
  local fd = ffi.C.open(file, bit.bor(system_constants.O_RDONLY(),
                                      system_constants.O_CREAT()),
                              bit.bor(system_constants.S_IRUSR(),
                                      system_constants.S_IWUSR()))
  if fd == -1 then
    log.warn("unable to pre-create '", file ,"' file: ",
             ffi.string(ffi.C.strerror(ffi.errno())))

  else
    ffi.C.close(fd)
  end
end


local function gen_default_dhparams(kong_config)
  for _, name in ipairs({ kong_config.nginx_http_ssl_dhparam, kong_config.nginx_stream_ssl_dhparam }) do
    local pem
    if name then
      pem = openssl_pkey.paramgen({
        type = "DH",
        group = name,
      })
    end

    if pem then
      local ssl_path = pl_path.join(kong_config.prefix, "ssl")
      if not pl_path.exists(ssl_path) then
        local ok, err = pl_dir.makepath(ssl_path)
        if not ok then
          return nil, err
        end
      end

      local param_file = pl_path.join(ssl_path, name .. ".pem")
      if not pl_path.exists(param_file) then
        log.verbose("generating %s DH parameters", name)
        local fd = assert(io.open(param_file, "w+b"))
        assert(fd:write(pem))
        fd:close()
      end
    end
  end

  return true
end


local function gen_default_ssl_cert(kong_config, target)
  -- create SSL folder
  local ok, err = pl_dir.makepath(pl_path.join(kong_config.prefix, "ssl"))
  if not ok then
    return nil, err
  end

  for _, suffix in ipairs({ "", "_ecdsa" }) do
    local ssl_cert, ssl_cert_key
    if target == "admin" then
      ssl_cert = kong_config["admin_ssl_cert_default" .. suffix]
      ssl_cert_key = kong_config["admin_ssl_cert_key_default" .. suffix]

    elseif target == "status" then
      ssl_cert = kong_config["status_ssl_cert_default" .. suffix]
      ssl_cert_key = kong_config["status_ssl_cert_key_default" .. suffix]

    else
      ssl_cert = kong_config["ssl_cert_default" .. suffix]
      ssl_cert_key = kong_config["ssl_cert_key_default" .. suffix]
    end

    if not pl_path.exists(ssl_cert) and not pl_path.exists(ssl_cert_key) then
      log.verbose("generating %s SSL certificate (", ssl_cert, ") and key (", ssl_cert_key, ") for ", target or "proxy", " listener")

      local key
      if suffix == "_ecdsa" then
        key = openssl_pkey.new { type = "EC", curve = "prime256v1" }
      else
        key = openssl_pkey.new { bits = 2048 }
      end

      local crt = x509.new()
      assert(crt:set_pubkey(key))
      assert(crt:set_version(3))
      assert(crt:set_serial_number(openssl_bignum.from_binary(openssl_rand.bytes(16))))

      -- last for 20 years
      local now = os.time()
      assert(crt:set_not_before(now))
      assert(crt:set_not_after(now + 86400 * 20 * 365))

      local name = assert(x509_name.new()
        :add("C", "US")
        :add("ST", "California")
        :add("L", "San Francisco")
        :add("O", "Kong")
        :add("OU", "IT Department")
        :add("CN", "localhost"))

      assert(crt:set_subject_name(name))
      assert(crt:set_issuer_name(name))

      -- Not a CA
      assert(crt:set_basic_constraints { CA = false })
      assert(crt:set_basic_constraints_critical(true))

      -- Only allowed to be used for TLS connections (client or server)
      assert(crt:add_extension(x509_extension.new("extendedKeyUsage",
                                                  "serverAuth,clientAuth")))

      -- RFC-3280 4.2.1.2
      assert(crt:add_extension(x509_extension.new("subjectKeyIdentifier", "hash", {
        subject = crt
      })))

      -- All done; sign
      assert(crt:sign(key))

      do -- write key out
        pre_create_private_file(ssl_cert_key)
        local fd = assert(io.open(ssl_cert_key, "w+b"))
        local pem = assert(key:to_PEM("private"))
        assert(fd:write(pem))
        fd:close()
      end

      do -- write cert out
        local fd = assert(io.open(ssl_cert, "w+b"))
        local pem = assert(crt:to_PEM())
        assert(fd:write(pem))
        fd:close()
      end

    else
      log.verbose("%s SSL certificate found at %s", target or "default", ssl_cert)
    end
  end

  return true
end


local function gen_trusted_certs_combined_file(combined_filepath, paths)

  log.verbose("generating trusted certs combined file in ",
              combined_filepath)

  local fd = assert(io.open(combined_filepath, "w"))

  for _, path in ipairs(paths) do
    fd:write(pl_file.read(path))
    fd:write("\n")
  end

  io.close(fd)
end


local function get_ulimit()
  local ok, _, stdout, stderr = pl_utils.executeex "ulimit -n"
  if not ok then
    return nil, stderr
  end
  local sanitized_limit = pl_stringx.strip(stdout)
  if sanitized_limit:lower():match("unlimited") then
    return 65536
  else
    return tonumber(sanitized_limit)
  end
end

local function compile_conf(kong_config, conf_template)
  -- computed config properties for templating
  local compile_env = {
    _escape = ">",
    pairs = pairs,
    ipairs = ipairs,
    tostring = tostring
  }

  do
    local worker_rlimit_nofile_auto
    if kong_config.nginx_main_directives then
      for _, directive in ipairs(kong_config.nginx_main_directives) do
        if directive.name == "worker_rlimit_nofile" then
          if directive.value == "auto" then
            worker_rlimit_nofile_auto = directive
          end
          break
        end
      end
    end

    local worker_connections_auto
    if kong_config.nginx_events_directives then
      for _, directive in ipairs(kong_config.nginx_events_directives) do
        if directive.name == "worker_connections" then
          if directive.value == "auto" then
            worker_connections_auto = directive
          end
          break
        end
      end
    end

    if worker_connections_auto or worker_rlimit_nofile_auto then
      local value, err = get_ulimit()
      if not value then
        return nil, err
      end

      value = math.min(value, 16384)

      if worker_rlimit_nofile_auto then
        worker_rlimit_nofile_auto.value = value
      end

      if worker_connections_auto then
        worker_connections_auto.value = value
      end
    end
  end

  compile_env = pl_tablex.merge(compile_env, kong_config, true) -- union
  compile_env.dns_resolver = table.concat(compile_env.dns_resolver, " ")
  compile_env.lua_package_path = (compile_env.lua_package_path or "") .. ";" ..
                                 (os.getenv("LUA_PATH") or "")
  compile_env.lua_package_cpath = (compile_env.lua_package_cpath or "") .. ";" ..
                                  (os.getenv("LUA_CPATH") or "")

  local post_template, err = pl_template.substitute(conf_template, compile_env)
  if not post_template then
    return nil, "failed to compile nginx config template: " .. err
  end

  return string.gsub(post_template, "(${%b{}})", function(w)
    local name = w:sub(4, -3)
    return compile_env[name:lower()] or ""
  end)
end

local function write_env_file(path, data)
  os.remove(path)

  local c = require "lua_system_constants"

  local flags = bit.bor(c.O_CREAT(), c.O_WRONLY())
  local mode  = bit.bor(c.S_IRUSR(), c.S_IWUSR(), c.S_IRGRP())

  local fd = ffi.C.open(path, flags, mode)
  if fd < 0 then
    local errno = ffi.errno()
    return nil, "unable to open env path " .. path .. " (" ..
                ffi.string(ffi.C.strerror(errno)) .. ")"
  end

  local ok = ffi.C.close(fd)
  if ok ~= 0 then
    local errno = ffi.errno()
    return nil, "failed to close fd (" ..
                ffi.string(ffi.C.strerror(errno)) .. ")"
  end

  local file, err = io.open(path, "w+")
  if not file then
    return nil, "unable to open env path " .. path .. " (" .. err .. ")"
  end

  local ok, err = file:write(data)

  file:close()

  if not ok then
    return nil, "unable to write env path " .. path .. " (" .. err .. ")"
  end

  return true
end

local function compile_kong_conf(kong_config)
  return compile_conf(kong_config, kong_nginx_template)
end

local function compile_kong_stream_conf(kong_config)
  return compile_conf(kong_config, kong_nginx_stream_template)
end

local function compile_nginx_conf(kong_config, template)
  template = template or default_nginx_template
  return compile_conf(kong_config, template)
end

local function prepare_prefix(kong_config, nginx_custom_template_path)
  log.verbose("preparing nginx prefix directory at %s", kong_config.prefix)

  if not pl_path.exists(kong_config.prefix) then
    log("prefix directory %s not found, trying to create it", kong_config.prefix)
    local ok, err = pl_dir.makepath(kong_config.prefix)
    if not ok then
      return nil, err
    end
  elseif not pl_path.isdir(kong_config.prefix) then
    return nil, kong_config.prefix .. " is not a directory"
  end

  -- create directories in prefix
  for _, dir in ipairs {"logs", "pids"} do
    local ok, err = pl_dir.makepath(pl_path.join(kong_config.prefix, dir))
    if not ok then
      return nil, err
    end
  end

  -- create log files in case they don't already exist
  if not pl_path.exists(kong_config.nginx_err_logs) then
    local ok, err = pl_file.write(kong_config.nginx_err_logs, "")
    if not ok then
      return nil, err
    end
  end
  if not pl_path.exists(kong_config.nginx_acc_logs) then
    local ok, err = pl_file.write(kong_config.nginx_acc_logs, "")
    if not ok then
      return nil, err
    end
  end
  if not pl_path.exists(kong_config.admin_acc_logs) then
    local ok, err = pl_file.write(kong_config.admin_acc_logs, "")
    if not ok then
      return nil, err
    end
  end

  -- generate default SSL certs if needed
  do
    for _, target in ipairs({ "proxy", "admin", "status" }) do
      local ssl_enabled = kong_config[target .. "_ssl_enabled"]
      if not ssl_enabled and target == "proxy" then
        ssl_enabled = kong_config.stream_proxy_ssl_enabled
      end

      local prefix
      if target == "proxy" then
        prefix = ""
      else
        prefix = target .. "_"
      end

      local ssl_cert = kong_config[prefix .. "ssl_cert"]
      local ssl_cert_key = kong_config[prefix .. "ssl_cert_key"]

      if ssl_enabled and #ssl_cert == 0 and #ssl_cert_key == 0 then
        log.verbose("SSL enabled on ", target, ", no custom certificate set: using default certificates")
        local ok, err = gen_default_ssl_cert(kong_config, target)
        if not ok then
          return nil, err
        end

        ssl_cert[1]     = kong_config[prefix .. "ssl_cert_default"]
        ssl_cert_key[1] = kong_config[prefix .. "ssl_cert_key_default"]
        ssl_cert[2]     = kong_config[prefix .. "ssl_cert_default_ecdsa"]
        ssl_cert_key[2] = kong_config[prefix .. "ssl_cert_key_default_ecdsa"]
      end
    end
  end

  if kong_config.lua_ssl_trusted_certificate_combined then
    gen_trusted_certs_combined_file(
      kong_config.lua_ssl_trusted_certificate_combined,
      kong_config.lua_ssl_trusted_certificate
    )
  end

  -- check ulimit
  local ulimit, err = get_ulimit()
  if not ulimit then return nil, err
  elseif ulimit < 4096 then
    log.warn([[ulimit is currently set to "%d". For better performance set it]] ..
             [[ to at least "4096" using "ulimit -n"]], ulimit)
  end

  -- compile Nginx configurations
  local nginx_template
  if nginx_custom_template_path then
    if not pl_path.exists(nginx_custom_template_path) then
      return nil, "no such file: " .. nginx_custom_template_path
    end
    nginx_template = pl_file.read(nginx_custom_template_path)
  end

  if kong_config.proxy_ssl_enabled or
     kong_config.stream_proxy_ssl_enabled or
     kong_config.admin_ssl_enabled or
     kong_config.status_ssl_enabled
  then
    gen_default_dhparams(kong_config)
  end

  -- write NGINX conf
  local nginx_conf, err = compile_nginx_conf(kong_config, nginx_template)
  if not nginx_conf then
    return nil, err
  end
  pl_file.write(kong_config.nginx_conf, nginx_conf)

  -- write Kong's HTTP NGINX conf
  local nginx_kong_conf, err = compile_kong_conf(kong_config)
  if not nginx_kong_conf then
    return nil, err
  end
  pl_file.write(kong_config.nginx_kong_conf, nginx_kong_conf)

  -- write Kong's stream NGINX conf
  local nginx_kong_stream_conf, err = compile_kong_stream_conf(kong_config)
  if not nginx_kong_stream_conf then
    return nil, err
  end
  pl_file.write(kong_config.nginx_kong_stream_conf, nginx_kong_stream_conf)

  -- testing written NGINX conf
  local ok, err = nginx_signals.check_conf(kong_config)
  if not ok then
    return nil, err
  end

  -- write kong.conf in prefix (for workers and CLI)
  local buf = {
    "# *************************",
    "# * DO NOT EDIT THIS FILE *",
    "# *************************",
    "# This configuration file is auto-generated. If you want to modify",
    "# the Kong configuration please edit/create the original `kong.conf`",
    "# file. Any modifications made here will be lost.",
    "# Start Kong with `--vv` to show where it is looking for that file.",
    "",
  }

  for k, v in pairs(kong_config) do
    if type(v) == "table" then
      if (getmetatable(v) or {}).__tostring then
        -- the 'tostring' meta-method knows how to serialize
        v = tostring(v)
      else
        v = table.concat(v, ",")
      end
    end
    if v ~= "" then
      buf[#buf+1] = k .. " = " .. tostring(v)
    end
  end

  local ok, err = write_env_file(kong_config.kong_env,
                                 table.concat(buf, "\n") .. "\n")
  if not ok then
    return nil, err
  end

  return true
end

return {
  get_ulimit = get_ulimit,
  prepare_prefix = prepare_prefix,
  compile_conf = compile_conf,
  compile_kong_conf = compile_kong_conf,
  compile_kong_stream_conf = compile_kong_stream_conf,
  compile_nginx_conf = compile_nginx_conf,
  gen_default_ssl_cert = gen_default_ssl_cert,
  write_env_file = write_env_file,
}
