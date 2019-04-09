-- Kong, the biggest ape in town
--
--     /\  ____
--     <> ( oo )
--     <>_| ^^ |_
--     <>   @    \
--    /~~\ . . _ |
--   /~~~~\    | |
--  /~~~~~~\/ _| |
--  |[][][]/ / [m]
--  |[][][[m]
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[][][]|
--  |[|--|]|
--  |[|  |]|
--  ========
-- ==========
-- |[[    ]]|
-- ==========


pcall(require, "luarocks.loader")
require "resty.core"


local constants = require "kong.constants"
do
  -- let's ensure the required shared dictionaries are
  -- declared via lua_shared_dict in the Nginx conf

  for _, dict in ipairs(constants.DICTS) do
    if not ngx.shared[dict] then
      return error("missing shared dict '" .. dict .. "' in Nginx "          ..
                   "configuration, are you using a custom template? "        ..
                   "Make sure the 'lua_shared_dict " .. dict .. " [SIZE];' " ..
                   "directive is defined.")
    end
  end

  -- if we're running `nginx -t` then don't initialize
  if os.getenv("KONG_NGINX_CONF_CHECK") then
    return {
      init = function() end,
    }
  end
end


require("kong.globalpatches")()


local kong_global = require "kong.global"
local PHASES = kong_global.phases


_G.kong = kong_global.new() -- no versioned PDK for plugins for now


local DB = require "kong.db"
local dns = require "kong.tools.dns"
local utils = require "kong.tools.utils"
local lapis = require "lapis"
local pl_utils = require "pl.utils"
local http_tls = require "http.tls"
local openssl_ssl = require "openssl.ssl"
local openssl_pkey = require "openssl.pkey"
local openssl_x509 = require "openssl.x509"
local runloop = require "kong.runloop.handler"
local mesh = require "kong.runloop.mesh"
local singletons = require "kong.singletons"
local ngx_balancer = require "ngx.balancer"
local kong_resty_ctx = require "kong.resty.ctx"
local certificate = require "kong.runloop.certificate"
local plugins_iterator = require "kong.runloop.plugins_iterator"
local balancer_execute = require("kong.runloop.balancer").execute
local kong_error_handlers = require "kong.error_handlers"


local kong             = kong
local ngx              = ngx
local header           = ngx.header
local ngx_log          = ngx.log
local ngx_ERR          = ngx.ERR
local ngx_WARN         = ngx.WARN
local ngx_CRIT         = ngx.CRIT
local ngx_DEBUG        = ngx.DEBUG
local table            = table
local ipairs           = ipairs
local assert           = assert
local tostring         = tostring
local coroutine        = coroutine
local getmetatable     = getmetatable
local registry         = debug.getregistry()
local get_last_failure = ngx_balancer.get_last_failure
local set_current_peer = ngx_balancer.set_current_peer
local set_ssl_ctx      = ngx_balancer.set_ssl_ctx
local set_timeouts     = ngx_balancer.set_timeouts
local set_more_tries   = ngx_balancer.set_more_tries


local ffi = require "ffi"
local cast = ffi.cast
local voidpp = ffi.typeof("void**")


local TLS_SCHEMES = {
  https = true,
  tls = true,
}


local configured_plugins
local loaded_plugins
local schema_state


local function sort_plugins_for_execution(kong_conf, db, plugin_list)
  -- sort plugins by order of execution
  table.sort(plugin_list, function(a, b)
    local priority_a = a.handler.PRIORITY or 0
    local priority_b = b.handler.PRIORITY or 0
    return priority_a > priority_b
  end)

  -- add reports plugin if not disabled
  if kong_conf.anonymous_reports then
    local reports = require "kong.reports"

    reports.configure_ping(kong_conf)
    reports.add_ping_value("database_version", db.infos.db_ver)
    reports.toggle(true)

    plugin_list[#plugin_list+1] = {
      name = "reports",
      handler = reports,
    }
  end
end


local function execute_plugins(ctx, phase, load_configuration)
  for plugin, plugin_conf in plugins_iterator(ctx, loaded_plugins,
    configured_plugins,
    load_configuration) do
    kong_global.set_named_ctx(kong, "plugin", plugin_conf)
    kong_global.set_namespaced_log(kong, plugin.name)

    plugin.handler[phase](plugin.handler, plugin_conf)

    kong_global.reset_log(kong)
  end
end


local function flush_delayed_response(ctx)
  ctx.delay_response = false

  if type(ctx.delayed_response_callback) == "function" then
    ctx.delayed_response_callback(ctx)
    return -- avoid tail call
  end

  kong.response.exit(ctx.delayed_response.status_code,
    ctx.delayed_response.content,
    ctx.delayed_response.headers)
end


-- Kong public context handlers.
-- @section kong_handlers


local Kong = {}


function Kong.init()
  -- special math.randomseed from kong.globalpatches not taking any argument.
  -- Must only be called in the init or init_worker phases, to avoid
  -- duplicated seeds.
  math.randomseed()

  local pl_path = require "pl.path"
  local conf_loader = require "kong.conf_loader"

  -- check if kong global is the correct one
  if not kong.version then
    error("configuration error: make sure your template is not setting a " ..
          "global named 'kong' (please use 'Kong' instead)")
  end

  -- retrieve kong_config
  local conf_path = pl_path.join(ngx.config.prefix(), ".kong_env")
  local config = assert(conf_loader(conf_path))

  -- Set up default ssl client context
  local default_client_ssl_ctx
  if set_ssl_ctx then
    default_client_ssl_ctx = http_tls.new_client_context()
    default_client_ssl_ctx:setVerify(openssl_ssl.VERIFY_NONE)
    default_client_ssl_ctx:setAlpnProtos { "http/1.1" }

    -- TODO: copy proxy_ssl_* flags?
    if config.client_ssl then
      local pem_key = assert(pl_utils.readfile(config.client_ssl_cert_key))
      default_client_ssl_ctx:setPrivateKey(openssl_pkey.new(pem_key))
      -- XXX: intermediary certs are NYI https://github.com/wahern/luaossl/issues/123
      local pem_cert = assert(pl_utils.readfile(config.client_ssl_cert))
      default_client_ssl_ctx:setCertificate(openssl_x509.new(pem_cert))
    end
  else
      ngx_log(ngx_WARN, "missing \"ngx.balancer\".set_ssl_ctx API. ",
                        "Dynamic client SSL_CTX* will be unavailable")
  end

  kong_global.init_pdk(kong, config, nil) -- nil: latest PDK

  local db = assert(DB.new(config))
  assert(db:init_connector())

  schema_state = assert(db:schema_state())
  if schema_state.needs_bootstrap  then
    error("database needs bootstrap; run 'kong migrations bootstrap'")
  elseif schema_state.new_migrations then
    error("new migrations available; run 'kong migrations list'")
  end
  --[[
  if schema_state.pending_migrations then
    assert(db:load_pending_migrations(schema_state.pending_migrations))
  end
  --]]

  assert(db:connect())
  assert(db.plugins:check_db_against_config(config.loaded_plugins))

  -- LEGACY
  singletons.dns = dns(config)
  singletons.configuration = config
  singletons.db = db
  -- /LEGACY

  do
    local origins = {}

    for _, v in ipairs(config.origins) do
      -- Validated in conf_loader
      local from_scheme, from_authority, to_scheme, to_authority =
        v:match("^(%a[%w+.-]*)://([^=]+:[%d]+)=(%a[%w+.-]*)://(.+)$")

      local from = assert(utils.normalize_ip(from_authority))
      local to = assert(utils.normalize_ip(to_authority))
      local from_origin = from_scheme:lower() .. "://" .. utils.format_host(from)

      to.scheme = to_scheme

      if to.port == nil then
        if to_scheme == "http" then
          to.port = 80
        elseif to_scheme == "https" then
          to.port = 443
        else
          error("scheme has unknown default port")
        end
      end

      origins[from_origin] = to
    end

    singletons.origins = origins
  end

  kong.db = db
  kong.dns = singletons.dns
  kong.default_client_ssl_ctx = default_client_ssl_ctx

  if ngx.config.subsystem == "stream" or config.proxy_ssl_enabled then
    certificate.init()
  end

  if kong.configuration.database ~= "off" then
    mesh.init()
  end

  -- Load plugins as late as possible so that everything is set up
  loaded_plugins = assert(db.plugins:load_plugin_schemas(config.loaded_plugins))
  sort_plugins_for_execution(config, db, loaded_plugins)

  runloop.init.after()

  db:close()
end


local function list_migrations(migtable)
  local list = {}
  for _, t in ipairs(migtable) do
    local mignames = {}
    for _, mig in ipairs(t.migrations) do
      table.insert(mignames, mig.name)
    end

    table.insert(list, string.format("%s (%s)", t.subsystem,
                       table.concat(mignames, ", ")))
  end

  return table.concat(list, " ")
end


function Kong.init_worker()
  kong_global.set_phase(kong, PHASES.init_worker)

  -- special math.randomseed from kong.globalpatches not taking any argument.
  -- Must only be called in the init or init_worker phases, to avoid
  -- duplicated seeds.
  math.randomseed()


  -- init DB


  local ok, err = kong.db:init_worker()
  if not ok then
    ngx_log(ngx_CRIT, "could not init DB: ", err)
    return
  end

  if ngx.worker.id() == 0 then
    if schema_state.missing_migrations then
      ngx_log(ngx.WARN, "missing migrations: ",
              list_migrations(schema_state.missing_migrations))
    end

    if schema_state.pending_migrations then
      ngx_log(ngx.INFO, "starting with pending migrations: ",
              list_migrations(schema_state.pending_migrations))
    end
  end

  local worker_events, err = kong_global.init_worker_events()
  if not worker_events then
    ngx_log(ngx_CRIT, "could not start inter-worker events: ", err)
    return
  end
  kong.worker_events = worker_events

  local cluster_events, err = kong_global.init_cluster_events(kong.configuration, kong.db)
  if not cluster_events then
    ngx_log(ngx_CRIT, "could not create cluster_events: ", err)
    return
  end
  kong.cluster_events = cluster_events

  local cache, err = kong_global.init_cache(kong.configuration, cluster_events, worker_events)
  if not cache then
    ngx_log(ngx_CRIT, "could not create kong cache: ", err)
    return
  end
  kong.cache = cache

  -- LEGACY
  singletons.cache          = cache
  singletons.worker_events  = worker_events
  singletons.cluster_events = cluster_events
  -- /LEGACY

  kong.db:set_events_handler(worker_events)

  runloop.init_worker.before()


  -- run plugins init_worker context


  for _, plugin in ipairs(loaded_plugins) do
    kong_global.set_namespaced_log(kong, plugin.name)
    plugin.handler:init_worker()
    kong_global.reset_log(kong)
  end
end


function Kong.ssl_certificate()
  kong_global.set_phase(kong, PHASES.certificate)

  local ctx = ngx.ctx

  runloop.certificate.before(ctx)

  configured_plugins = runloop.get_plugins()
  execute_plugins(ctx, "certificate", true)
end


function Kong.balancer()
  kong_global.set_phase(kong, PHASES.balancer)

  local ctx = ngx.ctx
  local balancer_data = ctx.balancer_data
  local tries = balancer_data.tries
  local current_try = {}

  balancer_data.try_count = balancer_data.try_count + 1
  tries[balancer_data.try_count] = current_try

  runloop.balancer.before(ctx)

  if balancer_data.try_count > 1 then
    -- only call balancer on retry, first one is done in `runloop.preread.after`
    -- or `runloop.access.after` which runs in the prepread or access context and
    -- hence has less limitations than this balancer context where the retries
    -- are executed

    -- record failure data
    local previous_try = tries[balancer_data.try_count - 1]
    previous_try.state, previous_try.code = get_last_failure()

    -- Report HTTP status for health checks
    local balancer = balancer_data.balancer
    if balancer then
      if previous_try.state == "failed" then
        if previous_try.code == 504 then
          balancer.report_timeout(balancer_data.balancer_handle)
        else
          balancer.report_tcp_failure(balancer_data.balancer_handle)
        end

      else
        balancer.report_http_status(balancer_data.balancer_handle,
                                    previous_try.code)
      end
    end

    local ok, err, errcode = balancer_execute(balancer_data)
    if not ok then
      ngx_log(ngx_ERR, "failed to retry the dns/balancer resolver for ",
              tostring(balancer_data.host), "' with: ", tostring(err))
      return ngx.exit(errcode)
    end

  else
    -- first try, so set the max number of retries
    local retries = balancer_data.retries
    if retries > 0 then
      set_more_tries(retries)
    end
  end

  local ssl_ctx = balancer_data.ssl_ctx
  if TLS_SCHEMES[balancer_data.scheme] and ssl_ctx ~= nil then
    if not set_ssl_ctx then
      -- this API depends on an OpenResty patch
      ngx_log(ngx_ERR, "failed to set the upstream SSL_CTX*: missing ",
                       "\"ngx.balancer\".set_ssl_ctx API")
      return ngx.exit(500)
    end

    -- ensure a third-party (e.g. plugin) did not set an invalid type for
    -- this value as such mistakes could cause segfaults
    assert(getmetatable(ssl_ctx) == registry["SSL_CTX*"],
           "unknown userdata type, expected SSL_CTX*")
    local ok, err = set_ssl_ctx(cast(voidpp, ssl_ctx)[0])
    if not ok then
      ngx_log(ngx_ERR, "failed to set the upstream SSL_CTX*: ", err)
      return ngx.exit(500)
    end
  end

  current_try.ip   = balancer_data.ip
  current_try.port = balancer_data.port

  -- set the targets as resolved
  ngx_log(ngx_DEBUG, "setting address (try ", balancer_data.try_count, "): ",
                     balancer_data.ip, ":", balancer_data.port)
  local ok, err = set_current_peer(balancer_data.ip, balancer_data.port)
  if not ok then
    ngx_log(ngx_ERR, "failed to set the current peer (address: ",
            tostring(balancer_data.ip), " port: ", tostring(balancer_data.port),
            "): ", tostring(err))
    return ngx.exit(500)
  end

  ok, err = set_timeouts(balancer_data.connect_timeout / 1000,
                         balancer_data.send_timeout / 1000,
                         balancer_data.read_timeout / 1000)
  if not ok then
    ngx_log(ngx_ERR, "could not set upstream timeouts: ", err)
  end

  runloop.balancer.after(ctx)
end


function Kong.rewrite()
  kong_resty_ctx.stash_ref()
  kong_global.set_phase(kong, PHASES.rewrite)

  local ctx = ngx.ctx

  runloop.rewrite.before(ctx)

  -- we're just using the iterator, as in this rewrite phase no consumer nor
  -- route will have been identified, hence we'll just be executing the global
  -- plugins
  configured_plugins = runloop.get_plugins()
  execute_plugins(ctx, "rewrite", true)

  runloop.rewrite.after(ctx)
end


function Kong.preread()
  kong_global.set_phase(kong, PHASES.preread)

  local ctx = ngx.ctx

  runloop.preread.before(ctx)

  configured_plugins = runloop.get_plugins()
  execute_plugins(ctx, "preread", true)

  runloop.preread.after(ctx)
end


function Kong.access()
  kong_global.set_phase(kong, PHASES.access)

  local ctx = ngx.ctx

  runloop.access.before(ctx)

  ctx.delay_response = true

  for plugin, plugin_conf in plugins_iterator(ctx, loaded_plugins,
                                              configured_plugins, true) do
    if not ctx.delayed_response then
      kong_global.set_named_ctx(kong, "plugin", plugin_conf)
      kong_global.set_namespaced_log(kong, plugin.name)

      local err = coroutine.wrap(plugin.handler.access)(plugin.handler, plugin_conf)

      kong_global.reset_log(kong)

      if err then
        ctx.delay_response = false
        kong.log.err(err)
        return kong.response.exit(500, { message  = "An unexpected error occurred" })
      end
    end
  end

  if ctx.delayed_response then
    return flush_delayed_response(ctx)
  end

  ctx.delay_response = false

  runloop.access.after(ctx)
end


function Kong.header_filter()
  kong_global.set_phase(kong, PHASES.header_filter)

  local ctx = ngx.ctx

  runloop.header_filter.before(ctx)

  execute_plugins(ctx, "header_filter")

  runloop.header_filter.after(ctx)
end


function Kong.body_filter()
  kong_global.set_phase(kong, PHASES.body_filter)

  local ctx = ngx.ctx

  execute_plugins(ctx, "body_filter")

  runloop.body_filter.after(ctx)
end


function Kong.log()
  kong_global.set_phase(kong, PHASES.log)

  local ctx = ngx.ctx

  execute_plugins(ctx, "log")

  runloop.log.after(ctx)
end


function Kong.handle_error()
  kong_resty_ctx.apply_ref()

  local ctx = ngx.ctx

  ctx.KONG_UNEXPECTED = true

  if not ctx.plugins_for_request then
    configured_plugins = runloop.get_plugins()
    for _ in plugins_iterator(ctx, loaded_plugins, configured_plugins, true) do
      -- just build list of plugins
    end
  end

  return kong_error_handlers(ngx)
end


function Kong.serve_admin_api(options)
  kong_global.set_phase(kong, PHASES.admin_api)

  options = options or {}

  header["Access-Control-Allow-Origin"] = options.allow_origin or "*"

  if ngx.req.get_method() == "OPTIONS" then
    header["Access-Control-Allow-Methods"] = "GET, HEAD, PUT, PATCH, POST, DELETE"
    header["Access-Control-Allow-Headers"] = "Content-Type"

    return ngx.exit(204)
  end

  return lapis.serve("kong.api")
end


return Kong
