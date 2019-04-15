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
local tracing = require "kong.tracing"
local responses = require "kong.tools.responses"
local semaphore = require "ngx.semaphore"
local singletons = require "kong.singletons"
local DAOFactory = require "kong.dao.factory"
local kong_cache = require "kong.cache"
local ngx_balancer = require "ngx.balancer"
local kong_resty_ctx = require "kong.resty.ctx"
local certificate = require "kong.runloop.certificate"
local plugins_iterator = require "kong.runloop.plugins_iterator"
local balancer_execute = require("kong.runloop.balancer").execute
local kong_cluster_events = require "kong.cluster_events"
local kong_error_handlers = require "kong.error_handlers"

local internal_proxies = require "kong.enterprise_edition.proxies"
local vitals = require "kong.vitals"
local ee = require "kong.enterprise_edition"
local portal_auth = require "kong.portal.auth"
local portal_emails = require "kong.portal.emails"
local admin_emails = require "kong.enterprise_edition.admin.emails"
local invoke_plugin = require "kong.enterprise_edition.invoke_plugin"

local kong             = kong
local ngx              = ngx
local header           = ngx.header
local ngx_log          = ngx.log
local ngx_ERR          = ngx.ERR
local ngx_WARN         = ngx.WARN
local ngx_CRIT         = ngx.CRIT
local ngx_DEBUG        = ngx.DEBUG
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

local PLUGINS_MAP_CACHE_OPTS = { ttl = 0 }

local plugins_map_semaphore
local plugins_map_version
local configured_plugins
local loaded_plugins
local schema_state

local function build_plugins_map(db, version)
  local map = {}

  for plugin, err in db.plugins:each() do
    if err then
      return nil, err
    end

    map[plugin.name] = true
  end

  if version then
    plugins_map_version = version
  end

  configured_plugins = map

  return true
end

local function plugins_map_wrapper()
  local version, err = kong.cache:get("plugins_map:version",
                                      PLUGINS_MAP_CACHE_OPTS, utils.uuid)
  if err then
    return nil, "failed to retrieve plugins map version: " .. err
  end

  if plugins_map_version ~= version then
    local timeout = 60
    if singletons.configuration.database == "cassandra" then
      -- cassandra_timeout is defined in ms
      timeout = singletons.configuration.cassandra_timeout / 1000

    elseif singletons.configuration.database == "postgres" then
      -- pg_timeout is defined in ms
      timeout = singletons.configuration.pg_timeout / 1000
    end

    -- try to acquire the mutex (semaphore)
    local ok, err = plugins_map_semaphore:wait(timeout)
    if not ok then
      return nil, "failed to acquire plugins map rebuild mutex: " .. err
    end

    -- we have the lock but we might not have needed it. check the
    -- version again and rebuild if necessary
    version, err = kong.cache:get("plugins_map:version",
                                  PLUGINS_MAP_CACHE_OPTS, utils.uuid)
    if err then
      plugins_map_semaphore:post(1)
      return nil, "failed to re-retrieve plugins map version: " .. err
    end

    if plugins_map_version ~= version then
      -- we have the lock and we need to rebuild the map
      ngx_log(ngx_DEBUG, "rebuilding plugins map")

      local ok, err = build_plugins_map(kong.db, version)
      if not ok then
        plugins_map_semaphore:post(1)
        return nil, "failed to rebuild plugins map: " .. err
      end
    end

    plugins_map_semaphore:post(1)
  end

  return true
end

-- Kong public context handlers.
-- @section kong_handlers

local Kong = {}


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

    reports.add_ping_value("database", kong_conf.database)
    reports.add_ping_value("database_version", db.infos.db_ver)

    reports.toggle(true)

    local shm = ngx.shared

    local reported_entities = {
      a = "apis",
      r = "routes",
      c = "consumers",
      s = "services",
    }

    for k, v in pairs(reported_entities) do
      reports.add_ping_value(k, function()
        return shm["kong_reports_" .. v] and
          #shm["kong_reports_" .. v]:get_keys(70000)
      end)
    end

    plugin_list[#plugin_list+1] = {
      name = "reports",
      handler = reports,
    }
  end
end


function Kong.init()
  -- special math.randomseed from kong.globalpatches not taking any argument.
  -- Must only be called in the init or init_worker phases, to avoid
  -- duplicated seeds.
  math.randomseed()

  local pl_path = require "pl.path"
  local conf_loader = require "kong.conf_loader"
  local ip = require "kong.tools.ip"


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
  tracing.init(config)

  local err = ee.feature_flags_init(config)
  if err then
    error(tostring(err))
  end

  local db = assert(DB.new(config))
  tracing.connector_query_wrap(db.connector)
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

  local dao = assert(DAOFactory.new(config, db)) -- instantiate long-lived DAO
  local ok, err_t = dao:init()
  if not ok then
    error(tostring(err_t))
  end

  --assert(dao:are_migrations_uptodate())

  db.old_dao = dao

  assert(db.plugins:check_db_against_config(config.loaded_plugins))

  -- LEGACY
  singletons.ip = ip.init(config)
  singletons.dns = dns(config)
  singletons.dao = dao
  singletons.configuration = config
  singletons.db = db
  -- /LEGACY

  kong.license = ee.read_license_info()
  singletons.internal_proxies = internal_proxies.new()
  singletons.portal_emails = portal_emails.new(config)
  singletons.admin_emails = admin_emails.new(config)

  local reports = require "kong.reports"
  local l = kong.license and
            kong.license.license.payload.license_key or
            nil
  reports.add_immutable_value("license_key", l)
  reports.add_immutable_value("enterprise", true)

  if config.anonymous_reports then
    reports.add_ping_value("rbac_enforced", singletons.configuration.rbac ~= "off")
  end
  kong.vitals = vitals.new {
      db             = db,
      flush_interval = config.vitals_flush_interval,
      delete_interval_pg = config.vitals_delete_interval_pg,
      ttl_seconds    = config.vitals_ttl_seconds,
      ttl_minutes    = config.vitals_ttl_minutes,
  }

  do
    local origins = {}

    for i, v in ipairs(config.origins) do
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

  kong.dao = dao
  kong.db = db
  kong.dns = singletons.dns
  kong.default_client_ssl_ctx = default_client_ssl_ctx

  if ngx.config.subsystem == "stream" or config.proxy_ssl_enabled then
    certificate.init()
  end

  mesh.init()

  -- Load plugins as late as possible so that everything is set up
  loaded_plugins = assert(db.plugins:load_plugin_schemas(config.loaded_plugins))
  sort_plugins_for_execution(config, db, loaded_plugins)


  singletons.invoke_plugin = invoke_plugin.new {
    loaded_plugins = loaded_plugins,
    kong_global = kong_global,
  }

  local err
  plugins_map_semaphore, err = semaphore.new()
  if not plugins_map_semaphore then
    error("failed to create plugins map semaphore: " .. err)
  end

  plugins_map_semaphore:post(1) -- one resource, treat this as a mutex

  local _, err = build_plugins_map(db, "init")
  if err then
    error("error building initial plugins map: ", err)
  end

  assert(runloop.build_router(db, "init"))
  assert(runloop.build_api_router(dao, "init"))
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


  -- init DAO


  local ok, err = kong.dao:init_worker()
  if not ok then
    ngx_log(ngx_CRIT, "could not init DAO: ", err)
    return
  end


  if ngx.worker.id() == 0 then
    if schema_state.missing_migrations then
      ngx.log(ngx.WARN, "missing migrations: ",
              list_migrations(schema_state.missing_migrations))
    end

    if schema_state.pending_migrations then
      ngx.log(ngx.INFO, "starting with pending migrations: ",
              list_migrations(schema_state.pending_migrations))
    end
  end


  -- init inter-worker events


  local worker_events = require "resty.worker.events"


  local ok, err = worker_events.configure {
    shm = "kong_process_events", -- defined by "lua_shared_dict"
    timeout = 5,            -- life time of event data in shm
    interval = 1,           -- poll interval (seconds)

    wait_interval = 0.010,  -- wait before retry fetching event data
    wait_max = 0.5,         -- max wait time before discarding event
  }
  if not ok then
    ngx_log(ngx_CRIT, "could not start inter-worker events: ", err)
    return
  end


  -- init cluster_events


  local cluster_events, err = kong_cluster_events.new {
    db                      = kong.db,
    poll_interval           = kong.configuration.db_update_frequency,
    poll_offset             = kong.configuration.db_update_propagation,
  }
  if not cluster_events then
    ngx_log(ngx_CRIT, "could not create cluster_events: ", err)
    return
  end


  -- init cache


  local cache, err = kong_cache.new {
    cluster_events    = cluster_events,
    worker_events     = worker_events,
    propagation_delay = kong.configuration.db_update_propagation,
    ttl               = kong.configuration.db_cache_ttl,
    neg_ttl           = kong.configuration.db_cache_ttl,
    resurrect_ttl     = kong.configuration.resurrect_ttl,
    resty_lock_opts   = {
      exptime = 10,
      timeout = 5,
    },
  }
  if not cache then
    ngx_log(ngx_CRIT, "could not create kong cache: ", err)
    return
  end

  local ok, err = cache:get("router:version", { ttl = 0 }, function()
    return "init"
  end)
  if not ok then
    ngx_log(ngx_CRIT, "could not set router version in cache: ", err)
    return
  end

  local ok, err = cache:get("api_router:version", { ttl = 0 }, function()
    return "init"
  end)
  if not ok then
    ngx_log(ngx_CRIT, "could not set API router version in cache: ", err)
    return
  end

  local ok, err = cache:get("plugins_map:version", { ttl = 0 }, function()
    return "init"
  end)
  if not ok then
    ngx_log(ngx_CRIT, "could not set plugins map version in cache: ", err)
    return
  end

  -- vitals functions require a timer, so must start in worker context
  local ok, err = kong.vitals:init()
  if not ok then
    ngx.log(ngx.CRIT, "could not initialize vitals: ", err)
    return
  end

  -- LEGACY
  singletons.cache          = cache
  singletons.worker_events  = worker_events
  singletons.cluster_events = cluster_events
  -- /LEGACY


  kong.cache = cache
  kong.worker_events = worker_events
  kong.cluster_events = cluster_events

  kong.db:set_events_handler(worker_events)
  kong.dao:set_events_handler(worker_events)


  runloop.init_worker.before()


  -- run plugins init_worker context


  for _, plugin in ipairs(loaded_plugins) do
    kong_global.set_namespaced_log(kong, plugin.name)

    plugin.handler:init_worker()
  end

  ee.handlers.init_worker.after(ngx.ctx)
end

function Kong.ssl_certificate()
  kong_global.set_phase(kong, PHASES.certificate)

  local ctx = ngx.ctx

  runloop.certificate.before(ctx)

  local ok, err = plugins_map_wrapper()
  if not ok then
    ngx_log(ngx_CRIT, "could not ensure plugins map is up to date: ", err)
    return ngx.exit(ngx.ERROR)
  end

  local old_ws = ctx.workspaces
  for plugin, plugin_conf in plugins_iterator(ctx, loaded_plugins,
                                              configured_plugins, true) do
    -- run certificate phase in global scope
    ctx.workspaces = {}

    kong_global.set_namespaced_log(kong, plugin.name)
    plugin.handler:certificate(plugin_conf)
    kong_global.reset_log(kong)
  end

  ctx.workspaces = old_ws
  -- empty `plugins_for_request` table - this phase runs in a global scope, so
  -- such table will have plugins that aren't part of this request's workspaces
  ctx.plugins_for_request = {}
end

function Kong.balancer()
  local trace = tracing.trace("balancer")

  kong_global.set_phase(kong, PHASES.balancer)

  local ctx = ngx.ctx
  local balancer_data = ctx.balancer_data
  local tries = balancer_data.tries
  local current_try = {}
  balancer_data.try_count = balancer_data.try_count + 1
  tries[balancer_data.try_count] = current_try

  runloop.balancer.before(ctx)

  if balancer_data.try_count > 1 then
    -- only call balancer on retry, first one is done in `runloop.access.after`
    -- which runs in the ACCESS context and hence has less limitations than
    -- this BALANCER context where the retries are executed

    -- record failure data
    local previous_try = tries[balancer_data.try_count - 1]
    previous_try.state, previous_try.code = get_last_failure()

    -- Report HTTP status for health checks
    local balancer = balancer_data.balancer
    if balancer then
      local ip, port = balancer_data.ip, balancer_data.port

      if previous_try.state == "failed" then
        if previous_try.code == 504 then
          balancer.report_timeout(ip, port)
        else
          balancer.report_tcp_failure(ip, port)
        end

      else
        balancer.report_http_status(ip, port, previous_try.code)
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

  trace:finish()
end

function Kong.rewrite()
  kong_resty_ctx.stash_ref()
  kong_global.set_phase(kong, PHASES.rewrite)

  local ctx = ngx.ctx
  ctx.is_proxy_request = true

  runloop.rewrite.before(ctx)

  local ok, err = plugins_map_wrapper()
  if not ok then
    ngx_log(ngx_CRIT, "could not ensure plugins map is up to date: ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local old_ws = ctx.workspaces
  -- we're just using the iterator, as in this rewrite phase no consumer nor
  -- api will have been identified, hence we'll just be executing the global
  -- plugins
  for plugin, plugin_conf in plugins_iterator(ctx, loaded_plugins,
                                              configured_plugins, true) do
    -- run certificate phase in global scope
    ctx.workspaces = {}

    kong_global.set_named_ctx(kong, "plugin", plugin_conf)
    kong_global.set_namespaced_log(kong, plugin.name)

    plugin.handler:rewrite(plugin_conf)

    kong_global.reset_log(kong)
  end

  ctx.workspaces = old_ws
  -- empty `plugins_for_request` table - this phase runs in a global scope, so
  -- such table will have plugins that aren't part of this request's workspaces
  ctx.plugins_for_request = {}

  runloop.rewrite.after(ctx)
end

function Kong.preread()
  kong_global.set_phase(kong, PHASES.preread)

  local ctx = ngx.ctx

  runloop.preread.before(ctx)

  local ok, err = plugins_map_wrapper()
  if not ok then
    ngx_log(ngx_CRIT, "could not ensure plugins map is up to date: ", err)
    return ngx.exit(ngx.ERROR)
  end

  for plugin, plugin_conf in plugins_iterator(ctx, loaded_plugins,
                                              configured_plugins, true) do
    kong_global.set_named_ctx(kong, "plugin", plugin_conf)
    kong_global.set_namespaced_log(kong, plugin.name)

    plugin.handler:preread(plugin_conf)

    kong_global.reset_log(kong)
  end

  runloop.preread.after(ctx)
end

function Kong.access()
  kong_global.set_phase(kong, PHASES.access)

  local ctx = ngx.ctx

  runloop.access.before(ctx)

  ctx.delay_response = true

  local old_ws = ctx.workspaces
  for plugin, plugin_conf in plugins_iterator(ctx, loaded_plugins,
                                              configured_plugins, true) do
    if not ctx.delayed_response then
      kong_global.set_named_ctx(kong, "plugin", plugin_conf)
      kong_global.set_namespaced_log(kong, plugin.name)

      local err = coroutine.wrap(plugin.handler.access)(plugin.handler, plugin_conf)

      kong_global.reset_log(kong)

      if err then
        ctx.delay_response = false
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      local ok, err = portal_auth.verify_developer_status(ctx.authenticated_consumer)

      if not ok then
        ctx.delay_response = false
        return responses.send_HTTP_UNAUTHORIZED(err)
      end
    end
    ctx.workspaces = old_ws
  end

  if ctx.delayed_response then
    return responses.flush_delayed_response(ctx)
  end

  ctx.delay_response = false

  runloop.access.after(ctx)
  ee.handlers.access.after(ctx)
end

function Kong.header_filter()
  kong_global.set_phase(kong, PHASES.header_filter)

  local ctx = ngx.ctx

  runloop.header_filter.before(ctx)

  local old_ws = ctx.workspaces
  for plugin, plugin_conf in plugins_iterator(ctx, loaded_plugins,
                                              configured_plugins) do
    kong_global.set_named_ctx(kong, "plugin", plugin_conf)
    kong_global.set_namespaced_log(kong, plugin.name)

    plugin.handler:header_filter(plugin_conf)

    kong_global.reset_log(kong)
    ctx.workspaces = old_ws
  end

  runloop.header_filter.after(ctx)
  ee.handlers.header_filter.after(ctx)
end

function Kong.body_filter()
  kong_global.set_phase(kong, PHASES.body_filter)

  local ctx = ngx.ctx

  local old_ws = ctx.workspaces
  for plugin, plugin_conf in plugins_iterator(ctx, loaded_plugins,
                                              configured_plugins) do
    kong_global.set_named_ctx(kong, "plugin", plugin_conf)
    kong_global.set_namespaced_log(kong, plugin.name)

    plugin.handler:body_filter(plugin_conf)

    kong_global.reset_log(kong)
    ctx.workspaces = old_ws
  end

  runloop.body_filter.after(ctx)
end

function Kong.log()
  kong_global.set_phase(kong, PHASES.log)

  local ctx = ngx.ctx

  local old_ws = ctx.workspaces
  -- for request with no matching route, ctx.plugins_for_request would be empty
  -- and there would not be any workspace linked to request.
  -- So we would need to reload the plugins(global) which apply to the request by
  -- setting access_or_cert_ctx to true.
  for plugin, plugin_conf in plugins_iterator(ctx, loaded_plugins,
                                              configured_plugins,
                                              not ctx.workspaces) do
    kong_global.set_named_ctx(kong, "plugin", plugin_conf)
    kong_global.set_namespaced_log(kong, plugin.name)

    plugin.handler:log(plugin_conf)

    kong_global.reset_log(kong)
    ctx.workspaces = old_ws
  end

  runloop.log.after(ctx)
  ee.handlers.log.after(ctx, ngx.status)
end

function Kong.handle_error()
  kong_resty_ctx.apply_ref()

  local ctx = ngx.ctx

  ctx.KONG_UNEXPECTED = true

  local old_ws = ctx.workspaces
  if not ctx.plugins_for_request then
    for _ in plugins_iterator(ctx, loaded_plugins, configured_plugins, true) do
      -- just build list of plugins
      ctx.workspaces = old_ws
    end
  end

  return kong_error_handlers(ngx)
end

function Kong.serve_admin_api(options)
  kong_global.set_phase(kong, PHASES.admin_api)

  options = options or {}

  -- if we support authentication via plugin as well as via RBAC token, then
  -- use cors plugin in api/init.lua to process cors requests and
  -- support the right origins, headers, etc.
  if not singletons.configuration.admin_gui_auth then
    header["Access-Control-Allow-Origin"] = options.allow_origin or "*"

    if ngx.req.get_method() == "OPTIONS" then
      header["Access-Control-Allow-Methods"] = options.acam or
        "GET, HEAD, PATCH, POST, DELETE"
      header["Access-Control-Allow-Headers"] = options.acah or "Content-Type"

      return ngx.exit(204)
    end
  end

  local headers = ngx.req.get_headers()

  if headers["Kong-Request-Type"] == "editor"  then
    header["Access-Control-Allow-Origin"] = singletons.configuration.admin_gui_url or "*"
    header["Access-Control-Allow-Credentials"] = true
    header["Content-Type"] = 'text/html'

    return lapis.serve("kong.portal.gui")
  end

  return lapis.serve("kong.api")
end


function Kong.serve_portal_api()
  return lapis.serve("kong.portal")
end

function Kong.serve_portal_gui()
  return lapis.serve("kong.portal.gui")
end


return Kong
