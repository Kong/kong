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

require "luarocks.loader"
require "resty.core"
local constants = require "kong.constants"
local plugin_overwrite = require "kong.enterprise_edition.plugin_overwrite"

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
end

require("kong.core.globalpatches")()

local ip = require "kong.tools.ip"
local DB = require "kong.db"
local dns = require "kong.tools.dns"
local core = require "kong.core.handler"
local utils = require "kong.tools.utils"
local lapis = require "lapis"
local responses = require "kong.tools.responses"
local semaphore = require "ngx.semaphore"
local singletons = require "kong.singletons"
local DAOFactory = require "kong.dao.factory"
local kong_cache = require "kong.cache"
local ngx_balancer = require "ngx.balancer"
local plugins_iterator = require "kong.core.plugins_iterator"
local balancer_execute = require("kong.core.balancer").execute
local kong_cluster_events = require "kong.cluster_events"
local kong_error_handlers = require "kong.core.error_handlers"
local internal_proxies = require "kong.enterprise_edition.proxies"
local vitals = require "kong.vitals"
local ee = require "kong.enterprise_edition"
local portal_emails = require "kong.portal.emails"

local ngx              = ngx
local header           = ngx.header
local ngx_log          = ngx.log
local ngx_ERR          = ngx.ERR
local ngx_CRIT         = ngx.CRIT
local ngx_DEBUG        = ngx.DEBUG
local ipairs           = ipairs
local assert           = assert
local tostring         = tostring
local coroutine        = coroutine
local get_last_failure = ngx_balancer.get_last_failure
local set_current_peer = ngx_balancer.set_current_peer
local set_timeouts     = ngx_balancer.set_timeouts
local set_more_tries   = ngx_balancer.set_more_tries

local plugins_map_version
local plugins_map_semaphore

local PLUGINS_MAP_CACHE_OPTS = { ttl = 0 }
local PLUGINS_MAP_PAGE_SIZE = 1000

local function build_plugins_map(dao, version)
  local map = {}

  local rows, err, offset

  -- postgres implements paging offsets as an incrementing integer
  -- cassandra's driver uses the native protocol paging implementation
  -- so we rely on the DAO to feed us back the offset with each iteration.
  -- postgres requires an initial value of 1 to prevent a duplicate read of
  -- the first page
  if singletons.configuration.database == "postgres" then
    offset = 1
  end

  -- iterate through a series of pages (PLUGINS_MAP_PAGE_SIZE at a time)
  -- so as to avoid making a huge 'SELECT *' query on the proxy path during rebuilds
  while true do
    rows, err, offset = dao.plugins:find_page(nil, offset, PLUGINS_MAP_PAGE_SIZE)

    if not rows then
      return nil, tostring(err)
    end

    for _, row in ipairs(rows) do
      map[row.name] = true
    end

    if offset == nil then
      break
    end
  end

  for _, plugin in ipairs(singletons.internal_proxies.config.plugins) do
    map[plugin.name] = true
  end

  if version then
    plugins_map_version = version
  end

  singletons.configured_plugins = map

  return true
end

local function load_plugins(kong_conf, dao)
  local in_db_plugins, sorted_plugins = {}, {}

  ngx_log(ngx_DEBUG, "Discovering used plugins")

  local rows, err_t = dao.plugins:find_all()
  if not rows then
    return nil, tostring(err_t)
  end

  for _, row in ipairs(rows) do in_db_plugins[row.name] = true end

  -- check all plugins in DB are enabled/installed
  for plugin in pairs(in_db_plugins) do
    if not kong_conf.plugins[plugin] then
      return nil, plugin .. " plugin is in use but not enabled"
    end
  end

  -- load installed plugins
  for plugin in pairs(kong_conf.plugins) do
    if constants.DEPRECATED_PLUGINS[plugin] then
      ngx.log(ngx.WARN, "plugin '", plugin, "' has been deprecated")
    end

    local ok, handler = utils.load_module_if_exists("kong.plugins." .. plugin .. ".handler")
    if not ok then
      return nil, plugin .. " plugin is enabled but not installed;\n" .. handler
    end

    local ok, schema = utils.load_module_if_exists("kong.plugins." .. plugin .. ".schema")
    if not ok then
      return nil, "no configuration schema found for plugin: " .. plugin
    end

    local _, err = plugin_overwrite.add_overwrite(plugin, schema)
    if err then
      return nil, plugin .. " plugin schema overwrite error: " .. err
    end

    ngx_log(ngx_DEBUG, "Loading plugin: " .. plugin)

    sorted_plugins[#sorted_plugins+1] = {
      name = plugin,
      handler = handler(),
      schema = schema
    }
  end

  -- sort plugins by order of execution
  table.sort(sorted_plugins, function(a, b)
    local priority_a = a.handler.PRIORITY or 0
    local priority_b = b.handler.PRIORITY or 0
    return priority_a > priority_b
  end)

  -- add reports plugin if not disabled
  if kong_conf.anonymous_reports then
    local reports = require "kong.core.reports"

    local db_infos = dao:infos()
    reports.add_ping_value("database", kong_conf.database)
    reports.add_ping_value("database_version", db_infos.version)

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

    sorted_plugins[#sorted_plugins+1] = {
      name = "reports",
      handler = reports,
      schema = {},
    }
  end

  return sorted_plugins
end


-- Kong public context handlers.
-- @section kong_handlers

local Kong = {}

function Kong.init()
  local pl_path = require "pl.path"
  local conf_loader = require "kong.conf_loader"

  -- retrieve kong_config
  local conf_path = pl_path.join(ngx.config.prefix(), ".kong_env")
  local config = assert(conf_loader(conf_path))

  local err = ee.feature_flags_init(config)
  if err then
    error(tostring(err))
  end

  local db = assert(DB.new(config))
  assert(db:init_connector())

  local dao = assert(DAOFactory.new(config, db)) -- instantiate long-lived DAO
  local ok, err_t = dao:init()
  if not ok then
    error(tostring(err_t))
  end

  assert(dao:are_migrations_uptodate())

  -- populate singletons
  singletons.ip = ip.init(config)
  singletons.dns = dns(config)
  singletons.configuration = config
  singletons.loaded_plugins = assert(load_plugins(config, dao))
  singletons.dao = dao
  singletons.configuration = config
  singletons.db = db
  singletons.license = ee.read_license_info()
  singletons.internal_proxies = internal_proxies.new()
  singletons.portal_emails = portal_emails.new(config)

  -- ee.internal_statsd_init() has to occur before build_plugins_map
  -- and after internal_proxies.new()
  local _, err = ee.internal_statsd_init()
  if err then
    error(tostring(err))
  end
  
  build_plugins_map(dao, "init")

  local reports = require "kong.core.reports"
  local l = singletons.license and
            singletons.license.license.payload.license_key or
            nil
  reports.add_immutable_value("license_key", l)
  reports.add_immutable_value("enterprise", true)

  if config.anonymous_reports then
    reports.add_ping_value("rbac_enforced", singletons.configuration.rbac ~= "off")
  end
  singletons.vitals = vitals.new {
      dao            = dao,
      flush_interval = config.vitals_flush_interval,
      delete_interval_pg = config.vitals_delete_interval_pg,
      ttl_seconds    = config.vitals_ttl_seconds,
      ttl_minutes    = config.vitals_ttl_minutes,
  }

  plugins_map_semaphore, err = semaphore.new()
  if not plugins_map_semaphore then
    ngx_log(ngx.CRIT, "failed to create plugins map semaphore: ", err)
  end

  plugins_map_semaphore:post(1) -- one resource, treat this as a mutex

  assert(core.build_router(db, "init"))
  assert(core.build_api_router(dao, "init"))
end

function Kong.init_worker()
  -- special math.randomseed from kong.core.globalpatches
  -- not taking any argument. Must be called only once
  -- and in the init_worker phase, to avoid duplicated
  -- seeds.
  math.randomseed()


  -- init DAO


  local ok, err = singletons.dao:init_worker()
  if not ok then
    ngx_log(ngx_CRIT, "could not init DB: ", err)
    return
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


  local dao_factory   = singletons.dao
  local configuration = singletons.configuration


  local cluster_events, err = kong_cluster_events.new {
    dao                     = dao_factory,
    poll_interval           = configuration.db_update_frequency,
    poll_offset             = configuration.db_update_propagation,
  }
  if not cluster_events then
    ngx_log(ngx_CRIT, "could not create cluster_events: ", err)
    return
  end


  -- init cache


  local cache, err = kong_cache.new {
    cluster_events    = cluster_events,
    worker_events     = worker_events,
    propagation_delay = configuration.db_update_propagation,
    ttl               = configuration.db_cache_ttl,
    neg_ttl           = configuration.db_cache_ttl,
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
    -- log the problem, but don't block further initialization
    ngx.log(ngx.CRIT, "could not set router version in cache: ", err)
  end


  -- vitals functions require a timer, so must start in worker context
  local ok, err = singletons.vitals:init()
  if not ok then
    ngx.log(ngx.CRIT, "could not initialize vitals: ", err)
    return
  end

  local ok, err = cache:get("api_router:version", { ttl = 0 }, function()
    return "init"
  end)
  if not ok then
    ngx_log(ngx_CRIT, "could not set API router version in cache: ", err)
    return
  end


  singletons.cache          = cache
  singletons.worker_events  = worker_events
  singletons.cluster_events = cluster_events


  singletons.db:set_events_handler(worker_events)
  singletons.dao:set_events_handler(worker_events)

  plugins_map_version = cache:get("plugins_map:version",
                                  PLUGINS_MAP_CACHE_OPTS,
                                  function() return "init" end)
  if err then
    ngx_log(ngx_CRIT, "could not set plugins_map version in cache: ", err)
    return
  end

  core.init_worker.before()


  -- run plugins init_worker context


  for _, plugin in ipairs(singletons.loaded_plugins) do
    plugin.handler:init_worker()
  end

  ee.handlers.init_worker.after(ngx.ctx)
end

function Kong.ssl_certificate()
  local ctx = ngx.ctx
  core.certificate.before(ctx)

  local old_ws = ctx.workspaces
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins,
                                              singletons.configured_plugins, true) do
    -- run certificate phase in global scope
    ctx.workspaces = {}
    plugin.handler:certificate(plugin_conf)
  end
  ctx.workspaces = old_ws
  -- empty `plugins_for_request` table - this phase runs in a global scope, so
  -- such table will have plugins that aren't part of this request's workspaces
  ctx.plugins_for_request = {}
end

function Kong.balancer()
  local ctx = ngx.ctx
  local addr = ctx.balancer_address
  local tries = addr.tries
  local current_try = {}
  addr.try_count = addr.try_count + 1
  tries[addr.try_count] = current_try

  core.balancer.before()

  if addr.try_count > 1 then
    -- only call balancer on retry, first one is done in `core.access.after` which runs
    -- in the ACCESS context and hence has less limitations than this BALANCER context
    -- where the retries are executed

    -- record failure data
    local previous_try = tries[addr.try_count - 1]
    previous_try.state, previous_try.code = get_last_failure()

    -- Report HTTP status for health checks
    if addr.balancer then
      if previous_try.state == "failed" then
        addr.balancer.report_tcp_failure(addr.ip, addr.port)
        if previous_try.code == 504 then
          addr.balancer.report_timeout(addr.ip, addr.port)
        else
          addr.balancer.report_tcp_failure(addr.ip, addr.port)
        end
      else
        addr.balancer.report_http_status(addr.ip, addr.port, previous_try.code)
      end
    end

    local ok, err, errcode = balancer_execute(addr)
    if not ok then
      ngx_log(ngx_ERR, "failed to retry the dns/balancer resolver for ",
              tostring(addr.host), "' with: ", tostring(err))
      return ngx.exit(errcode)
    end

  else
    -- first try, so set the max number of retries
    local retries = addr.retries
    if retries > 0 then
      set_more_tries(retries)
    end
  end

  current_try.ip   = addr.ip
  current_try.port = addr.port

  -- set the targets as resolved
  ngx_log(ngx_DEBUG, "setting address (try ", addr.try_count, "): ",
                     addr.ip, ":", addr.port)
  local ok, err = set_current_peer(addr.ip, addr.port)
  if not ok then
    ngx_log(ngx_ERR, "failed to set the current peer (address: ",
            tostring(addr.ip), " port: ", tostring(addr.port),"): ",
            tostring(err))
    return ngx.exit(500)
  end

  ok, err = set_timeouts(addr.connect_timeout / 1000,
                         addr.send_timeout / 1000,
                         addr.read_timeout / 1000)
  if not ok then
    ngx_log(ngx_ERR, "could not set upstream timeouts: ", err)
  end

  core.balancer.after()
end

local function plugins_map_wrapper()
  local version, err = singletons.cache:get("plugins_map:version",
                                            PLUGINS_MAP_CACHE_OPTS,
                                            utils.uuid)
  if err then
    ngx_log(ngx.CRIT, "could not ensure plugins_map is up to date: ", err)

    return false

  elseif plugins_map_version ~= version then
    -- try to acquire the mutex (semaphore)

    local ok, err = plugins_map_semaphore:wait(10)

    if ok then
      -- we have the lock but we might not have needed it. check the
      -- version again and rebuild if necessary

      version, err = singletons.cache:get("plugins_map:version",
                                          PLUGINS_MAP_CACHE_OPTS,
                                          utils.uuid)
      if err then
        ngx_log(ngx.CRIT, "could not ensure plugins_map is up to date: ", err)

        plugins_map_semaphore:post(1)

        return false

      elseif plugins_map_version ~= version then
        -- we have the lock and we need to rebuild the map. go go gadget!

        ngx_log(ngx_DEBUG, "rebuilding plugins_map")

        local ok, err = build_plugins_map(singletons.dao, version)
        if not ok then
          ngx_log(ngx.CRIT, "could not rebuild plugins_map: ", err)
        end
      end

      plugins_map_semaphore:post(1)
    else
      ngx_log(ngx.CRIT, "could not acquire plugins_map update mutex: ", err)

      return false
    end
  end

  return true
end

function Kong.rewrite()
  local ctx = ngx.ctx
  ctx.is_proxy_request = true

  core.rewrite.before(ctx)

  local ok = plugins_map_wrapper()
  if not ok then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local old_ws = ctx.workspaces
  -- we're just using the iterator, as in this rewrite phase no consumer nor
  -- api will have been identified, hence we'll just be executing the global
  -- plugins
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins,
                                              singletons.configured_plugins, true) do
    -- run certificate phase in global scope
    ctx.workspaces = {}
    plugin.handler:rewrite(plugin_conf)
  end
  ctx.workspaces = old_ws
  -- empty `plugins_for_request` table - this phase runs in a global scope, so
  -- such table will have plugins that aren't part of this request's workspaces
  ctx.plugins_for_request = {}

  core.rewrite.after(ctx)
end

function Kong.access()
  local ctx = ngx.ctx

  core.access.before(ctx)

  ctx.delay_response = true

  local old_ws = ctx.workspaces
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins,
                                              singletons.configured_plugins, true) do
    if not ctx.delayed_response then
      local err = coroutine.wrap(plugin.handler.access)(plugin.handler, plugin_conf)
      if err then
        ctx.delay_response = false
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end
    end
    ctx.workspaces = old_ws
  end

  if ctx.delayed_response then
    return responses.flush_delayed_response(ctx)
  end

  ctx.delay_response = false

  core.access.after(ctx)
  ee.handlers.access.after(ctx)
end

function Kong.header_filter()
  local ctx = ngx.ctx
  core.header_filter.before(ctx)

  local old_ws = ctx.workspaces
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins,
                                              singletons.configured_plugins) do
    plugin.handler:header_filter(plugin_conf)
    ctx.workspaces = old_ws
  end

  core.header_filter.after(ctx)
  ee.handlers.header_filter.after(ctx)
end

function Kong.body_filter()
  local ctx = ngx.ctx
  local old_ws = ctx.workspaces
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins,
                                              singletons.configured_plugins) do
    plugin.handler:body_filter(plugin_conf)
    ctx.workspaces = old_ws
  end

  core.body_filter.after(ctx)
end

function Kong.log()
  local ctx = ngx.ctx
  local old_ws = ctx.workspaces
  for plugin, plugin_conf in plugins_iterator(singletons.loaded_plugins,
                                              singletons.configured_plugins) do
    plugin.handler:log(plugin_conf)
    ctx.workspaces = old_ws
  end

  core.log.after(ctx)
  ee.handlers.log.after(ctx, ngx.status)
end

function Kong.handle_error()
  return kong_error_handlers(ngx)
end

function Kong.serve_admin_api(options)
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

  return lapis.serve("kong.api")
end

function Kong.serve_portal_api()
  return lapis.serve(require("kong.portal").app)
end

function Kong.serve_portal_gui()
  return lapis.serve("kong.portal.gui")
end

return Kong
