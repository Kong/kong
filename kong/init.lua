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
local runloop = require "kong.runloop.handler"
local tracing = require "kong.tracing"
local singletons = require "kong.singletons"
local declarative = require "kong.db.declarative"
local ngx_balancer = require "ngx.balancer"
local kong_resty_ctx = require "kong.resty.ctx"
local certificate = require "kong.runloop.certificate"
local concurrency = require "kong.concurrency"
local cache_warmup = require "kong.cache_warmup"
local balancer_execute = require("kong.runloop.balancer").execute
local kong_error_handlers = require "kong.error_handlers"
local migrations_utils = require "kong.cmd.utils.migrations"


local internal_proxies = require "kong.enterprise_edition.proxies"
local vitals = require "kong.vitals"
local ee = require "kong.enterprise_edition"
local portal_auth = require "kong.portal.auth"
local portal_emails = require "kong.portal.emails"
local admin_emails = require "kong.enterprise_edition.admin.emails"
local portal_router = require "kong.portal.router"
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
local get_last_failure = ngx_balancer.get_last_failure
local set_current_peer = ngx_balancer.set_current_peer
local set_timeouts     = ngx_balancer.set_timeouts
local set_more_tries   = ngx_balancer.set_more_tries


local declarative_entities
local schema_state


local reset_kong_shm
do
  local preserve_keys = {
    "events:requests",
    "kong:node_id",
  }

  reset_kong_shm = function()
    local preserved = {}

    for _, key in ipairs(preserve_keys) do
      -- ignore errors
      preserved[key] = ngx.shared.kong:get(key)
    end

    ngx.shared.kong:flush_all()
    ngx.shared.kong:flush_expired(0)

    for _, key in ipairs(preserve_keys) do
      ngx.shared.kong:set(key, preserved[key])
    end
  end
end


local function execute_plugins_iterator(plugins_iterator, ctx, phase)
  -- XXX EE: Check we don't update old_ws twice
  local old_ws = ctx.workspaces
  for plugin, configuration in plugins_iterator:iterate(ctx, phase) do
    kong_global.set_named_ctx(kong, "plugin", configuration)
    kong_global.set_namespaced_log(kong, plugin.name)

    plugin.handler[phase](plugin.handler, configuration)

    kong_global.reset_log(kong)
    ctx.workspaces = old_ws
  end
end


local function execute_cache_warmup(kong_config)
  if kong_config.database == "off" then
    return true
  end

  if ngx.worker.id() == 0 then
    local ok, err = cache_warmup.execute(kong_config.db_cache_warmup_entities)
    if not ok then
      return nil, err
    end
  end

  return true
end


-- Kong public context handlers.
-- @section kong_handlers

local Kong = {}


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


local function parse_declarative_config(kong_config)
  if kong_config.database ~= "off" then
    return {}
  end

  if not kong_config.declarative_config then
    return {}
  end

  local dc = declarative.new_config(kong_config)
  local entities, err = dc:parse_file(kong_config.declarative_config)
  if not entities then
    return nil, "error parsing declarative config file " ..
                kong_config.declarative_config .. ":\n" .. err
  end

  return entities
end


local function load_declarative_config(kong_config, entities)
  if kong_config.database ~= "off" then
    return true
  end

  if not kong_config.declarative_config then
    -- no configuration yet, just build empty plugins iterator
    local ok, err = runloop.build_plugins_iterator(utils.uuid())
    if not ok then
      error("error building initial plugins iterator: " .. err)
    end
    return true
  end

  local opts = {
    name = "declarative_config",
  }
  return concurrency.with_worker_mutex(opts, function()
    local value = ngx.shared.kong:get("declarative_config:loaded")
    if value then
      return true
    end

    local ok, err = declarative.load_into_cache(entities)
    if not ok then
      return nil, err
    end

    kong.log.notice("declarative config loaded from ",
                    kong_config.declarative_config)

    ok, err = runloop.build_plugins_iterator(utils.uuid())
    if not ok then
      error("error building initial plugins iterator: " .. err)
    end

    assert(runloop.build_router("init"))

    ok, err = ngx.shared.kong:safe_set("declarative_config:loaded", true)
    if not ok then
      kong.log.warn("failed marking declarative_config as loaded: ", err)
    end

    return true
  end)
end


function Kong.init()
  reset_kong_shm()

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
  migrations_utils.check_state(schema_state, db)

  if schema_state.missing_migrations or schema_state.pending_migrations then
    if schema_state.missing_migrations then
      ngx_log(ngx_WARN, "database is missing some migrations:\n",
                        schema_state.missing_migrations)
  end

  if schema_state.pending_migrations then
      ngx_log(ngx_WARN, "database has pending migrations:\n",
                        schema_state.pending_migrations)
    end
  end

  assert(db:connect())
  assert(db.plugins:check_db_against_config(config.loaded_plugins))

  -- LEGACY
  singletons.dns = dns(config)
  singletons.configuration = config
  singletons.db = db
  -- /LEGACY

  kong.license = ee.read_license_info()
  singletons.internal_proxies = internal_proxies.new()
  singletons.portal_emails = portal_emails.new(config)
  singletons.admin_emails = admin_emails.new(config)
  singletons.portal_router = portal_router.new(db)

  local reports = require "kong.reports"
  local l = kong.license and
            kong.license.license.payload.license_key or
            nil
  reports.add_immutable_value("license_key", l)
  reports.add_immutable_value("enterprise", true)

  if config.anonymous_reports then
    reports.add_ping_value("rbac_enforced", singletons.configuration.rbac ~= "off")
    reports.add_entity_reports()
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

  kong.db = db
  kong.dns = singletons.dns

  if ngx.config.subsystem == "stream" or config.proxy_ssl_enabled then
    certificate.init()
  end

  -- Load plugins as late as possible so that everything is set up
  assert(db.plugins:load_plugin_schemas(config.loaded_plugins))


  singletons.invoke_plugin = invoke_plugin.new {
    loaded_plugins = db.plugins:get_handlers(),
    kong_global = kong_global,
  }

  if kong.configuration.database == "off" then
  local err
    declarative_entities, err = parse_declarative_config(kong.configuration)
    if not declarative_entities then
      error(err)
  end

  else
    local ok, err = runloop.build_plugins_iterator("init")
    if not ok then
      error("error building initial plugins: " .. tostring(err))
  end

    assert(runloop.build_router("init"))
  end

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
      ngx.log(ngx.WARN, "missing migrations: ",
              list_migrations(schema_state.missing_migrations))
    end

    if schema_state.pending_migrations then
      ngx.log(ngx.INFO, "starting with pending migrations: ",
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

  -- vitals functions require a timer, so must start in worker context
  local ok, err = kong.vitals:init()
  if not ok then
    ngx.log(ngx.CRIT, "could not initialize vitals: ", err)
    return
  end

  local cache, err = kong_global.init_cache(kong.configuration, cluster_events, worker_events, kong.vitals)
  if not cache then
    ngx_log(ngx_CRIT, "could not create kong cache: ", err)
    return
  end
  kong.cache = cache

  ok, err = runloop.set_init_versions_in_cache()
  if not ok then
    ngx_log(ngx_CRIT, err)
    return
  end

  -- LEGACY
  singletons.cache          = cache
  singletons.worker_events  = worker_events
  singletons.cluster_events = cluster_events
  -- /LEGACY

  kong.db:set_events_handler(worker_events)

  ok, err = load_declarative_config(kong.configuration, declarative_entities)
  if not ok then
    ngx_log(ngx_CRIT, "error loading declarative config file: ", err)
    return
  end

  ok, err = execute_cache_warmup(kong.configuration)
  if not ok then
    ngx_log(ngx_ERR, "could not warm up the DB cache: ", err)
  end

  runloop.init_worker.before()


  -- run plugins init_worker context
  ok, err = runloop.update_plugins_iterator()
  if not ok then
    ngx_log(ngx_CRIT, "error building plugins iterator: ", err)
    return
  end

  local plugins_iterator = runloop.get_plugins_iterator()
  for plugin, _ in plugins_iterator:iterate(nil, "init_worker") do
    kong_global.set_namespaced_log(kong, plugin.name)
    plugin.handler:init_worker()
    kong_global.reset_log(kong)
  end

  ee.handlers.init_worker.after(ngx.ctx)
end

function Kong.ssl_certificate()
  kong_global.set_phase(kong, PHASES.certificate)

  local mock_ctx = {} -- ctx is not available in cert phase, use table instead

  runloop.certificate.before(mock_ctx)

  local plugins_iterator = runloop.get_updated_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, mock_ctx, "certificate")
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

  -- On HTTPS requests, the plugins iterator is already updated in the ssl_certificate phase
  local plugins_iterator
  if ngx.var.https == "on" then
    plugins_iterator = runloop.get_plugins_iterator()
  else
    plugins_iterator = runloop.get_updated_plugins_iterator()
  end

  execute_plugins_iterator(plugins_iterator, ctx, "rewrite")

  runloop.rewrite.after(ctx)
end

function Kong.preread()
  kong_global.set_phase(kong, PHASES.preread)

  local ctx = ngx.ctx

  runloop.preread.before(ctx)

  local plugins_iterator = runloop.get_updated_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, ctx, "preread")

  runloop.preread.after(ctx)
end

function Kong.access()
  kong_global.set_phase(kong, PHASES.access)

  local ctx = ngx.ctx

  runloop.access.before(ctx)

  ctx.delay_response = true

  local old_ws = ctx.workspaces
  local plugins_iterator = runloop.get_plugins_iterator()
  for plugin, plugin_conf in plugins_iterator:iterate(ctx, "access") do
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

      local ok, err = portal_auth.verify_developer_status(ctx.authenticated_consumer)

      if not ok then
        ctx.delay_response = false
        return kong.response.exit(401, { message = err })
      end
    end
    ctx.workspaces = old_ws
  end

  if ctx.delayed_response then
    return flush_delayed_response(ctx)
  end

  ctx.delay_response = false

  runloop.access.after(ctx)
  ee.handlers.access.after(ctx)
end

function Kong.header_filter()
  kong_global.set_phase(kong, PHASES.header_filter)

  local ctx = ngx.ctx

  runloop.header_filter.before(ctx)

  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, ctx, "header_filter")

  runloop.header_filter.after(ctx)
  ee.handlers.header_filter.after(ctx)
end

function Kong.body_filter()
  kong_global.set_phase(kong, PHASES.body_filter)

  local ctx = ngx.ctx

  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, ctx, "body_filter")

  runloop.body_filter.after(ctx)
end

function Kong.log()
  kong_global.set_phase(kong, PHASES.log)

  local ctx = ngx.ctx

  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, ctx, "log")

  runloop.log.after(ctx)
  ee.handlers.log.after(ctx, ngx.status)
end

function Kong.handle_error()
  kong_resty_ctx.apply_ref()

  local ctx = ngx.ctx

  ctx.KONG_UNEXPECTED = true

  local old_ws = ctx.workspaces
  if not ctx.plugins then
    local plugins_iterator = runloop.get_updated_plugins_iterator()
    for _ in plugins_iterator:iterate(ctx, "content") do
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
        "GET, HEAD, PATCH, POST, PUT, DELETE"
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
  kong_global.set_phase(kong, PHASES.admin_api)

  return lapis.serve("kong.portal")
end

function Kong.serve_portal_gui()
  kong_global.set_phase(kong, PHASES.admin_api)

  return lapis.serve("kong.portal.gui")
end

function Kong.serve_portal_assets()
  kong_global.set_phase(kong, PHASES.admin_api)

   return lapis.serve("kong.portal.gui")
end

return Kong
