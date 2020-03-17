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


assert(package.loaded["resty.core"], "lua-resty-core must be loaded; make " ..
                                     "sure 'lua_load_resty_core' is not "..
                                     "disabled.")


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
local clustering = require "kong.clustering"
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
local go = require "kong.db.dao.plugins.go"


local kong             = kong
local ngx              = ngx
local now              = ngx.now
local update_time      = ngx.update_time
local var              = ngx.var
local arg              = ngx.arg
local header           = ngx.header
local ngx_log          = ngx.log
local ngx_ALERT        = ngx.ALERT
local ngx_CRIT         = ngx.CRIT
local ngx_ERR          = ngx.ERR
local ngx_WARN         = ngx.WARN
local ngx_INFO         = ngx.INFO
local ngx_DEBUG        = ngx.DEBUG
local subsystem        = ngx.config.subsystem
local type             = type
local error            = error
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


local stash_init_worker_error
local log_init_worker_errors
do
  local init_worker_errors
  local init_worker_errors_str
  local ctx_k = {}


  stash_init_worker_error = function(err)
    if err == nil then
      return
    end

    err = tostring(err)

    if not init_worker_errors then
      init_worker_errors = {}
    end

    table.insert(init_worker_errors, err)
    init_worker_errors_str = table.concat(init_worker_errors, ", ")

    return ngx_log(ngx_CRIT, "worker initialization error: ", err,
                             "; this node must be restarted")
  end


  log_init_worker_errors = function(ctx)
    if not init_worker_errors_str or ctx[ctx_k] then
      return
    end

    ctx[ctx_k] = true

    return ngx_log(ngx_ALERT, "unsafe request processing due to earlier ",
                              "initialization errors; this node must be ",
                              "restarted (", init_worker_errors_str, ")")
  end
end


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


local function execute_plugins_iterator(plugins_iterator, phase, ctx)
  for plugin, configuration in plugins_iterator:iterate(phase, ctx) do
    if ctx then
      if plugin.handler._go then
        ctx.ran_go_plugin = true
      end

      kong_global.set_named_ctx(kong, "plugin", plugin.handler)
    end

    kong_global.set_namespaced_log(kong, plugin.name)
    plugin.handler[phase](plugin.handler, configuration)
    kong_global.reset_log(kong)
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


local function get_now_ms()
  update_time()
  return now() * 1000 -- time is kept in seconds with millisecond resolution.
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

    ok, err = runloop.build_plugins_iterator("init")
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


local buffered_proxy
do
  local HTTP_METHODS = {
    GET       = ngx.HTTP_GET,
    HEAD      = ngx.HTTP_HEAD,
    PUT       = ngx.HTTP_PUT,
    POST      = ngx.HTTP_POST,
    DELETE    = ngx.HTTP_DELETE,
    OPTIONS   = ngx.HTTP_OPTIONS,
    MKCOL     = ngx.HTTP_MKCOL,
    COPY      = ngx.HTTP_COPY,
    MOVE      = ngx.HTTP_MOVE,
    PROPFIND  = ngx.HTTP_PROPFIND,
    PROPPATCH = ngx.HTTP_PROPPATCH,
    LOCK      = ngx.HTTP_LOCK,
    UNLOCK    = ngx.HTTP_UNLOCK,
    PATCH     = ngx.HTTP_PATCH,
    TRACE     = ngx.HTTP_TRACE,
  }

  buffered_proxy = function(ctx)
    ngx.req.read_body()

    local options = {
      always_forward_body = true,
      share_all_vars      = true,
      method              = HTTP_METHODS[ngx.req.get_method()],
      ctx                 = ctx,
    }

    local res = ngx.location.capture("/kong_buffered_http", options)
    if res.truncated then
      ngx.status = 502
      return kong_error_handlers(ngx)
    end

    return kong.response.exit(res.status, res.body, res.header)
  end
end


-- Kong public context handlers.
-- @section kong_handlers

local Kong = {}


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
  local config = assert(conf_loader(conf_path, nil, { from_kong_env = true }))

  kong_global.init_pdk(kong, config, nil) -- nil: latest PDK

  local db = assert(DB.new(config))
  assert(db:init_connector())

  schema_state = assert(db:schema_state())
  migrations_utils.check_state(schema_state)

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

  kong.db = db
  kong.dns = singletons.dns

  if subsystem == "stream" or config.proxy_ssl_enabled then
    certificate.init()
  end

  clustering.init(config)

  -- Load plugins as late as possible so that everything is set up
  assert(db.plugins:load_plugin_schemas(config.loaded_plugins))

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


function Kong.init_worker()
  kong_global.set_phase(kong, PHASES.init_worker)

  -- special math.randomseed from kong.globalpatches not taking any argument.
  -- Must only be called in the init or init_worker phases, to avoid
  -- duplicated seeds.
  math.randomseed()


  -- init DB


  local ok, err = kong.db:init_worker()
  if not ok then
    stash_init_worker_error("failed to instantiate 'kong.db' module: " .. err)
    return
  end


  if ngx.worker.id() == 0 then
    if schema_state.missing_migrations then
      ngx_log(ngx_WARN, "missing migrations: ",
              list_migrations(schema_state.missing_migrations))
    end

    if schema_state.pending_migrations then
      ngx_log(ngx_INFO, "starting with pending migrations: ",
              list_migrations(schema_state.pending_migrations))
    end
  end

  local worker_events, err = kong_global.init_worker_events()
  if not worker_events then
    stash_init_worker_error("failed to instantiate 'kong.worker_events' " ..
                            "module: " .. err)
    return
  end
  kong.worker_events = worker_events

  local cluster_events, err = kong_global.init_cluster_events(kong.configuration, kong.db)
  if not cluster_events then
    stash_init_worker_error("failed to instantiate 'kong.cluster_events' " ..
                            "module: " .. err)
    return
  end
  kong.cluster_events = cluster_events

  local cache, err = kong_global.init_cache(kong.configuration, cluster_events, worker_events)
  if not cache then
    stash_init_worker_error("failed to instantiate 'kong.cache' module: " ..
                            err)
    return
  end
  kong.cache = cache

  local core_cache, err = kong_global.init_core_cache(kong.configuration, cluster_events, worker_events)
  if not cache then
    stash_init_worker_error("failed to instantiate 'kong.core_cache' module: " ..
                            err)
    return
  end
  kong.core_cache = core_cache

  ok, err = runloop.set_init_versions_in_cache()
  if not ok then
    stash_init_worker_error(err) -- 'err' fully formatted
    return
  end

  -- LEGACY
  singletons.cache          = cache
  singletons.core_cache     = core_cache
  singletons.worker_events  = worker_events
  singletons.cluster_events = cluster_events
  -- /LEGACY

  kong.db:set_events_handler(worker_events)

  ok, err = load_declarative_config(kong.configuration, declarative_entities)
  if not ok then
    stash_init_worker_error("failed to load declarative config file: " .. err)
    return
  end

  ok, err = execute_cache_warmup(kong.configuration)
  if not ok then
    ngx_log(ngx_ERR, "failed to warm up the DB cache: " .. err)
  end

  runloop.init_worker.before()


  -- run plugins init_worker context
  ok, err = runloop.update_plugins_iterator()
  if not ok then
    stash_init_worker_error("failed to build the plugins iterator: " .. err)
    return
  end

  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "init_worker")

  if go.is_on() then
    go.manage_pluginserver()
  end

  clustering.init_worker(kong.configuration)
end


function Kong.preread()
  local ctx = ngx.ctx
  if not ctx.KONG_PROCESSING_START then
    ctx.KONG_PROCESSING_START = get_now_ms()
  end

  if not ctx.KONG_PREREAD_START then
    ctx.KONG_PREREAD_START = ctx.KONG_PROCESSING_START
  end

  kong_global.set_phase(kong, PHASES.preread)

  log_init_worker_errors(ctx)

  runloop.preread.before(ctx)

  local plugins_iterator = runloop.get_updated_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "preread", ctx)

  if not ctx.service then
    ctx.KONG_PREREAD_ENDED_AT = get_now_ms()
    ctx.KONG_PREREAD_TIME = ctx.KONG_PREREAD_ENDED_AT - ctx.KONG_PREREAD_START

    ngx_log(ngx_WARN, "no Service found with those values")
    return ngx.exit(503)
  end

  runloop.preread.after(ctx)

  ctx.KONG_PREREAD_ENDED_AT = get_now_ms()
  ctx.KONG_PREREAD_TIME = ctx.KONG_PREREAD_ENDED_AT - ctx.KONG_PREREAD_START

  -- we intent to proxy, though balancer may fail on that
  ctx.KONG_PROXIED = true
end


function Kong.ssl_certificate()
  kong_global.set_phase(kong, PHASES.certificate)

  -- this doesn't really work across the phases currently (OpenResty 1.13.6.2),
  -- but it returns a table (rewrite phase clears it)
  local ctx = ngx.ctx
  log_init_worker_errors(ctx)

  runloop.certificate.before(ctx)

  local plugins_iterator = runloop.get_updated_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "certificate", ctx)
end


function Kong.rewrite()
  if var.kong_proxy_mode == "grpc" then
    kong_resty_ctx.apply_ref() -- if kong_proxy_mode is gRPC, this is executing
    kong_resty_ctx.stash_ref() -- after an internal redirect. Restore (and restash)
                               -- context to avoid re-executing phases

    local ctx = ngx.ctx
    ctx.KONG_REWRITE_ENDED_AT = get_now_ms()
    ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT - ctx.KONG_REWRITE_START

    return
  end

  local ctx = ngx.ctx
  if not ctx.KONG_PROCESSING_START then
    ctx.KONG_PROCESSING_START = ngx.req.start_time() * 1000
  end

  if not ctx.KONG_REWRITE_START then
    ctx.KONG_REWRITE_START = get_now_ms()
  end

  kong_global.set_phase(kong, PHASES.rewrite)
  kong_resty_ctx.stash_ref()

  local is_https = var.https == "on"
  if not is_https then
    log_init_worker_errors(ctx)
  end

  runloop.rewrite.before(ctx)

  -- On HTTPS requests, the plugins iterator is already updated in the ssl_certificate phase
  local plugins_iterator
  if is_https then
    plugins_iterator = runloop.get_plugins_iterator()
  else
    plugins_iterator = runloop.get_updated_plugins_iterator()
  end

  execute_plugins_iterator(plugins_iterator, "rewrite", ctx)

  ctx.KONG_REWRITE_ENDED_AT = get_now_ms()
  ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT - ctx.KONG_REWRITE_START
end


function Kong.access()
  local ctx = ngx.ctx
  if not ctx.KONG_ACCESS_START then
    ctx.KONG_ACCESS_START = get_now_ms()

    if ctx.KONG_REWRITE_START and not ctx.KONG_REWRITE_ENDED_AT then
      ctx.KONG_REWRITE_ENDED_AT = ctx.KONG_ACCESS_START
      ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT - ctx.KONG_REWRITE_START
    end
  end

  kong_global.set_phase(kong, PHASES.access)

  runloop.access.before(ctx)

  ctx.delay_response = true

  local plugins_iterator = runloop.get_plugins_iterator()
  for plugin, plugin_conf in plugins_iterator:iterate("access", ctx) do
    if plugin.handler._go then
      ctx.ran_go_plugin = true
    end

    if not ctx.delayed_response then
      kong_global.set_named_ctx(kong, "plugin", plugin.handler)
      kong_global.set_namespaced_log(kong, plugin.name)

      local err = coroutine.wrap(plugin.handler.access)(plugin.handler, plugin_conf)
      if err then
        kong.log.err(err)
        ctx.delayed_response = {
          status_code = 500,
          content     = { message  = "An unexpected error occurred" },
        }
      end

      kong_global.reset_log(kong)
    end
  end

  if ctx.delayed_response then
    ctx.KONG_ACCESS_ENDED_AT = get_now_ms()
    ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT - ctx.KONG_ACCESS_START
    ctx.KONG_RESPONSE_LATENCY = ctx.KONG_ACCESS_ENDED_AT - ctx.KONG_PROCESSING_START

    return flush_delayed_response(ctx)
  end

  ctx.delay_response = false

  if not ctx.service then
    ctx.KONG_ACCESS_ENDED_AT = get_now_ms()
    ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT - ctx.KONG_ACCESS_START
    ctx.KONG_RESPONSE_LATENCY = ctx.KONG_ACCESS_ENDED_AT - ctx.KONG_PROCESSING_START

    return kong.response.exit(503, { message = "no Service found with those values"})
  end

  runloop.access.after(ctx)

  ctx.KONG_ACCESS_ENDED_AT = get_now_ms()
  ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT - ctx.KONG_ACCESS_START

  -- we intent to proxy, though balancer may fail on that
  ctx.KONG_PROXIED = true

  if kong.ctx.core.buffered_proxying then
    return buffered_proxy(ctx)
  end
end


function Kong.balancer()
  -- This may be called multiple times, and no yielding here!
  local now_ms = get_now_ms()

  local ctx = ngx.ctx
  if not ctx.KONG_BALANCER_START then
    ctx.KONG_BALANCER_START = now_ms

    if subsystem == "stream" then
      if ctx.KONG_PREREAD_START and not ctx.KONG_PREREAD_ENDED_AT then
        ctx.KONG_PREREAD_ENDED_AT = ctx.KONG_BALANCER_START
        ctx.KONG_PREREAD_TIME = ctx.KONG_PREREAD_ENDED_AT -
                                ctx.KONG_PREREAD_START
      end

    else
      if ctx.KONG_REWRITE_START and not ctx.KONG_REWRITE_ENDED_AT then
        ctx.KONG_REWRITE_ENDED_AT = ctx.KONG_ACCESS_START or
                                    ctx.KONG_BALANCER_START
        ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT -
                                ctx.KONG_REWRITE_START
      end

      if ctx.KONG_ACCESS_START and not ctx.KONG_ACCESS_ENDED_AT then
        ctx.KONG_ACCESS_ENDED_AT = ctx.KONG_BALANCER_START
        ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT -
                               ctx.KONG_ACCESS_START
      end
    end
  end

  kong_global.set_phase(kong, PHASES.balancer)

  local balancer_data = ctx.balancer_data
  local tries = balancer_data.tries
  local current_try = {}
  balancer_data.try_count = balancer_data.try_count + 1
  tries[balancer_data.try_count] = current_try

  current_try.balancer_start = now_ms

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

      ctx.KONG_BALANCER_ENDED_AT = get_now_ms()
      ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_BALANCER_START
      ctx.KONG_PROXY_LATENCY = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_PROCESSING_START

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

    ctx.KONG_BALANCER_ENDED_AT = get_now_ms()
    ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_BALANCER_START
    ctx.KONG_PROXY_LATENCY = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_PROCESSING_START

    return ngx.exit(500)
  end

  ok, err = set_timeouts(balancer_data.connect_timeout / 1000,
                         balancer_data.send_timeout / 1000,
                         balancer_data.read_timeout / 1000)
  if not ok then
    ngx_log(ngx_ERR, "could not set upstream timeouts: ", err)
  end

  -- record overall latency
  ctx.KONG_BALANCER_ENDED_AT = get_now_ms()
  ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_BALANCER_START

  -- record try-latency
  local try_latency = ctx.KONG_BALANCER_ENDED_AT - current_try.balancer_start
  current_try.balancer_latency = try_latency

  -- time spent in Kong before sending the request to upstream
  -- start_time() is kept in seconds with millisecond resolution.
  ctx.KONG_PROXY_LATENCY = ctx.KONG_BALANCER_ENDED_AT - ctx.KONG_PROCESSING_START
end


function Kong.header_filter()
  local ctx = ngx.ctx
  if not ctx.KONG_PROCESSING_START then
    ctx.KONG_PROCESSING_START = ngx.req.start_time() * 1000
  end

  if not ctx.KONG_HEADER_FILTER_START then
    ctx.KONG_HEADER_FILTER_START = get_now_ms()

    if ctx.KONG_REWRITE_START and not ctx.KONG_REWRITE_ENDED_AT then
      ctx.KONG_REWRITE_ENDED_AT = ctx.KONG_BALANCER_START or
                                  ctx.KONG_ACCESS_START or
                                  ctx.KONG_HEADER_FILTER_START
      ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT -
                              ctx.KONG_REWRITE_START
    end

    if ctx.KONG_ACCESS_START and not ctx.KONG_ACCESS_ENDED_AT then
      ctx.KONG_ACCESS_ENDED_AT = ctx.KONG_BALANCER_START or
                                 ctx.KONG_HEADER_FILTER_START
      ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT -
                             ctx.KONG_ACCESS_START
    end

    if ctx.KONG_BALANCER_START and not ctx.KONG_BALANCER_ENDED_AT then
      ctx.KONG_BALANCER_ENDED_AT = ctx.KONG_HEADER_FILTER_START
      ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT -
                               ctx.KONG_BALANCER_START
    end
  end

  if ctx.KONG_PROXIED then
    ctx.KONG_WAITING_TIME = ctx.KONG_HEADER_FILTER_START -
                           (ctx.KONG_BALANCER_ENDED_AT or ctx.KONG_ACCESS_ENDED_AT)

    if not ctx.KONG_PROXY_LATENCY then
      ctx.KONG_PROXY_LATENCY = ctx.KONG_HEADER_FILTER_START - ctx.KONG_PROCESSING_START
    end

  elseif not ctx.KONG_RESPONSE_LATENCY then
    ctx.KONG_RESPONSE_LATENCY = ctx.KONG_HEADER_FILTER_START - ctx.KONG_PROCESSING_START
  end

  kong_global.set_phase(kong, PHASES.header_filter)

  runloop.header_filter.before(ctx)
  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "header_filter", ctx)
  runloop.header_filter.after(ctx)

  ctx.KONG_HEADER_FILTER_ENDED_AT = get_now_ms()
  ctx.KONG_HEADER_FILTER_TIME = ctx.KONG_HEADER_FILTER_ENDED_AT - ctx.KONG_HEADER_FILTER_START
end


function Kong.body_filter()
  local ctx = ngx.ctx
  if not ctx.KONG_BODY_FILTER_START then
    ctx.KONG_BODY_FILTER_START = get_now_ms()

    if ctx.KONG_REWRITE_START and not ctx.KONG_REWRITE_ENDED_AT then
      ctx.KONG_REWRITE_ENDED_AT = ctx.KONG_ACCESS_START or
                                  ctx.KONG_BALANCER_START or
                                  ctx.KONG_HEADER_FILTER_START or
                                  ctx.KONG_BODY_FILTER_START
      ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT -
                              ctx.KONG_REWRITE_START
    end

    if ctx.KONG_ACCESS_START and not ctx.KONG_ACCESS_ENDED_AT then
      ctx.KONG_ACCESS_ENDED_AT = ctx.KONG_BALANCER_START or
                                 ctx.KONG_HEADER_FILTER_START or
                                 ctx.KONG_BODY_FILTER_START
      ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT -
                             ctx.KONG_ACCESS_START
    end

    if ctx.KONG_BALANCER_START and not ctx.KONG_BALANCER_ENDED_AT then
      ctx.KONG_BALANCER_ENDED_AT = ctx.KONG_HEADER_FILTER_START or
                                   ctx.KONG_BODY_FILTER_START
      ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT -
                               ctx.KONG_BALANCER_START
    end

    if ctx.KONG_HEADER_FILTER_START and not ctx.KONG_HEADER_FILTER_ENDED_AT then
      ctx.KONG_HEADER_FILTER_ENDED_AT = ctx.KONG_BODY_FILTER_START
      ctx.KONG_HEADER_FILTER_TIME = ctx.KONG_HEADER_FILTER_ENDED_AT -
                                    ctx.KONG_HEADER_FILTER_START
    end
  end

  kong_global.set_phase(kong, PHASES.body_filter)

  if kong.ctx.core.response_body then
    arg[1] = kong.ctx.core.response_body
    arg[2] = true
  end

  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "body_filter", ctx)

  if not arg[2] then
    return
  end

  ctx.KONG_BODY_FILTER_ENDED_AT = get_now_ms()
  ctx.KONG_BODY_FILTER_TIME = ctx.KONG_BODY_FILTER_ENDED_AT - ctx.KONG_BODY_FILTER_START

  if ctx.KONG_PROXIED then
    -- time spent receiving the response (header_filter + body_filter)
    -- we could use $upstream_response_time but we need to distinguish the waiting time
    -- from the receiving time in our logging plugins (especially ALF serializer).
    ctx.KONG_RECEIVE_TIME = ctx.KONG_BODY_FILTER_ENDED_AT - (ctx.KONG_HEADER_FILTER_START or
                                                             ctx.KONG_BALANCER_ENDED_AT or
                                                             ctx.KONG_BALANCER_START or
                                                             ctx.KONG_ACCESS_ENDED_AT)
  end
end


function Kong.log()
  local ctx = ngx.ctx
  if not ctx.KONG_LOG_START then
    ctx.KONG_LOG_START = get_now_ms()
    if subsystem == "stream" then
      if ctx.KONG_PREREAD_START and not ctx.KONG_PREREAD_ENDED_AT then
        ctx.KONG_PREREAD_ENDED_AT = ctx.KONG_LOG_START
        ctx.KONG_PREREAD_TIME = ctx.KONG_PREREAD_ENDED_AT -
                                ctx.KONG_PREREAD_START
      end

      if ctx.KONG_BALANCER_START and not ctx.KONG_BALANCER_ENDED_AT then
        ctx.KONG_BALANCER_ENDED_AT = ctx.KONG_LOG_START
        ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT -
                                 ctx.KONG_BALANCER_START
      end

    else
      if ctx.KONG_BODY_FILTER_START and not ctx.KONG_BODY_FILTER_ENDED_AT then
        ctx.KONG_BODY_FILTER_ENDED_AT = ctx.KONG_LOG_START
        ctx.KONG_BODY_FILTER_TIME = ctx.KONG_BODY_FILTER_ENDED_AT -
                                    ctx.KONG_BODY_FILTER_START
      end

      if ctx.KONG_REWRITE_START and not ctx.KONG_REWRITE_ENDED_AT then
        ctx.KONG_REWRITE_ENDED_AT = ctx.KONG_ACCESS_START or
                                    ctx.KONG_BALANCER_START or
                                    ctx.KONG_HEADER_FILTER_START or
                                    ctx.BODY_FILTER_START or
                                    ctx.KONG_LOG_START
        ctx.KONG_REWRITE_TIME = ctx.KONG_REWRITE_ENDED_AT -
                                ctx.KONG_REWRITE_START
      end

      if ctx.KONG_ACCESS_START and not ctx.KONG_ACCESS_ENDED_AT then
        ctx.KONG_ACCESS_ENDED_AT = ctx.KONG_BALANCER_START or
                                   ctx.KONG_HEADER_FILTER_START or
                                   ctx.BODY_FILTER_START or
                                   ctx.KONG_LOG_START
        ctx.KONG_ACCESS_TIME = ctx.KONG_ACCESS_ENDED_AT -
                               ctx.KONG_ACCESS_START
      end

      if ctx.KONG_BALANCER_START and not ctx.KONG_BALANCER_ENDED_AT then
        ctx.KONG_BALANCER_ENDED_AT = ctx.KONG_HEADER_FILTER_START or
                                     ctx.BODY_FILTER_START or
                                     ctx.KONG_LOG_START
        ctx.KONG_BALANCER_TIME = ctx.KONG_BALANCER_ENDED_AT -
                                 ctx.KONG_BALANCER_START
      end

      if ctx.KONG_HEADER_FILTER_START and not ctx.KONG_HEADER_FILTER_ENDED_AT then
        ctx.KONG_HEADER_FILTER_ENDED_AT = ctx.BODY_FILTER_START or
                                          ctx.KONG_LOG_START
        ctx.KONG_HEADER_FILTER_TIME = ctx.KONG_HEADER_FILTER_ENDED_AT -
                                      ctx.KONG_HEADER_FILTER_START
      end
    end
  end

  kong_global.set_phase(kong, PHASES.log)

  local ctx = ngx.ctx

  local plugins_iterator = runloop.get_plugins_iterator()
  execute_plugins_iterator(plugins_iterator, "log", ctx)
  runloop.log.after(ctx)


  -- this is not used for now, but perhaps we need it later?
  --ctx.KONG_LOG_ENDED_AT = get_now_ms()
  --ctx.KONG_LOG_TIME = ctx.KONG_LOG_ENDED_AT - ctx.KONG_LOG_START
end


function Kong.handle_error()
  kong_resty_ctx.apply_ref()
  kong_global.set_phase(kong, PHASES.error)

  local ctx = ngx.ctx
  ctx.KONG_UNEXPECTED = true

  log_init_worker_errors(ctx)

  if not ctx.plugins then
    local plugins_iterator = runloop.get_updated_plugins_iterator()
    for _ in plugins_iterator:iterate("content", ctx) do
      -- just build list of plugins
    end
  end

  return kong_error_handlers(ctx)
end


local function serve_content(module, options)
  kong_global.set_phase(kong, PHASES.admin_api)

  local ctx = ngx.ctx
  ctx.KONG_PROCESSING_START = ngx.req.start_time() * 1000
  ctx.KONG_ADMIN_CONTENT_START = ctx.KONG_ADMIN_CONTENT_START or get_now_ms()


  log_init_worker_errors(ctx)

  options = options or {}

  header["Access-Control-Allow-Origin"] = options.allow_origin or "*"

  if ngx.req.get_method() == "OPTIONS" then
    header["Access-Control-Allow-Methods"] = "GET, HEAD, PUT, PATCH, POST, DELETE"
    header["Access-Control-Allow-Headers"] = "Content-Type"

    ctx.KONG_ADMIN_CONTENT_ENDED_AT = get_now_ms()
    ctx.KONG_ADMIN_CONTENT_TIME = ctx.KONG_ADMIN_CONTENT_ENDED_AT - ctx.KONG_ADMIN_CONTENT_START
    ctx.KONG_ADMIN_LATENCY = ctx.KONG_ADMIN_CONTENT_ENDED_AT - ctx.KONG_PROCESSING_START

    return ngx.exit(204)
  end

  lapis.serve(module)

  ctx.KONG_ADMIN_CONTENT_ENDED_AT = get_now_ms()
  ctx.KONG_ADMIN_CONTENT_TIME = ctx.KONG_ADMIN_CONTENT_ENDED_AT - ctx.KONG_ADMIN_CONTENT_START
  ctx.KONG_ADMIN_LATENCY = ctx.KONG_ADMIN_CONTENT_ENDED_AT - ctx.KONG_PROCESSING_START
end


function Kong.admin_content(options)
  return serve_content("kong.api", options)
end


-- TODO: deprecate the following alias
Kong.serve_admin_api = Kong.admin_content


function Kong.admin_header_filter()
  local ctx = ngx.ctx

  if not ctx.KONG_PROCESSING_START then
    ctx.KONG_PROCESSING_START = ngx.req.start_time() * 1000
  end

  if not ctx.KONG_ADMIN_HEADER_FILTER_START then
    ctx.KONG_ADMIN_HEADER_FILTER_START = get_now_ms()

    if ctx.KONG_ADMIN_CONTENT_START and not ctx.KONG_ADMIN_CONTENT_ENDED_AT then
      ctx.KONG_ADMIN_CONTENT_ENDED_AT = ctx.KONG_ADMIN_HEADER_FILTER_START
      ctx.KONG_ADMIN_CONTENT_TIME = ctx.KONG_ADMIN_CONTENT_ENDED_AT - ctx.KONG_ADMIN_CONTENT_START
    end

    if not ctx.KONG_ADMIN_LATENCY then
      ctx.KONG_ADMIN_LATENCY = ctx.KONG_ADMIN_HEADER_FILTER_START - ctx.KONG_PROCESSING_START
    end
  end

  if kong.configuration.enabled_headers[constants.HEADERS.ADMIN_LATENCY] then
    header[constants.HEADERS.ADMIN_LATENCY] = ctx.KONG_ADMIN_LATENCY
  end

  -- this is not used for now, but perhaps we need it later?
  --ctx.KONG_ADMIN_HEADER_FILTER_ENDED_AT = get_now_ms()
  --ctx.KONG_ADMIN_HEADER_FILTER_TIME = ctx.KONG_ADMIN_HEADER_FILTER_ENDED_AT - ctx.KONG_ADMIN_HEADER_FILTER_START
end


function Kong.status_content()
  return serve_content("kong.status")
end


Kong.status_header_filter = Kong.admin_header_filter


function Kong.serve_cluster_listener(options)
  log_init_worker_errors()

  kong_global.set_phase(kong, PHASES.cluster_listener)

  return clustering.handle_cp_websocket()
end


return Kong
