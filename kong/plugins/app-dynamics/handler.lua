-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local get_service = kong.router.get_service
local get_route = kong.router.get_route
local get_header = kong.request.get_header
local meta = require "kong.meta"

local appd
do
  local loaded, result = pcall(require, "kong.plugins.app-dynamics.appdynamics")
  if loaded then
    appd = result
  else
    kong.log.err("appdynamics shared library could not be loaded")
  end
end

local ffi = require "ffi"

local AppDynamicsHandler = {
  PRIORITY = 999999, -- Setting the priority for first to execute
  VERSION = meta.core_version,
}

local APPD_ENV_VARIABLE_PREFIX = "KONG_APPD_"
local APPD_SINGULARITY_HEADER = "singularityHeader"
local APPD_SDK_BT_TIMEOUT = 5 * 60

local envs = {}
if appd then
  -- read and populate all environment variables while we have access, if we need
  -- to retry later, there will be no access anymore (only in init_worker)
  local TYPE_STRING = 0
  local TYPE_NUMBER = 1
  local TYPE_BOOLEAN = 2
  local TYPE_SECRET_STRING = 3

  local function fetch_config_variable(name, type, default)
    local env_name = APPD_ENV_VARIABLE_PREFIX .. name
    local value = os.getenv(env_name)
    local err

    if value == nil and default == nil then
      kong.log.err("The mandatory AppDynamics environment variable " .. env_name .. " was not set")
    end

    local logged_value = value
    if not value then
      if default then
        logged_value = tostring(default) .. " [defaulted]"
      else
        logged_value = "[not set]"
      end
    elseif type == TYPE_SECRET_STRING and not kong.vault.is_reference(value) then
      logged_value = "(redacted)"
    end
    kong.log.debug("AppDynamics SDK config: ", env_name, "=", logged_value)
    if kong.vault.is_reference(value) then
      local vault_reference = value
      value, err = kong.vault.get(vault_reference)
      if err then
        kong.log.err("could not resolve vault reference " .. vault_reference .. " from environment variable " .. env_name .. ": " .. err)
        return
      end
    end

    if value == nil then
      value = default
    elseif type == TYPE_NUMBER then
      value = tonumber(value)
    elseif type == TYPE_BOOLEAN then
      value = value:upper() == "ON" or value:upper() == "TRUE" or value == "1"
    end

    if value then
      envs[name] = value
    end
  end

  -- Mandatory
  fetch_config_variable("CONTROLLER_HOST")
  fetch_config_variable("TIER_NAME")
  fetch_config_variable("CONTROLLER_ACCOUNT", TYPE_SECRET_STRING)
  fetch_config_variable("CONTROLLER_ACCESS_KEY", TYPE_SECRET_STRING)

  -- Optional
  fetch_config_variable("LOGGING_LEVEL", TYPE_NUMBER, appd.APPD_LOG_LEVEL_INFO)
  fetch_config_variable("LOGGING_LOG_DIR", TYPE_STRING, "/tmp/appd")
  fetch_config_variable("APP_NAME", TYPE_STRING, "Kong")
  fetch_config_variable("NODE_NAME", TYPE_STRING, kong.node.get_hostname())
  fetch_config_variable("CONTROLLER_PORT", TYPE_NUMBER, 443)
  fetch_config_variable("INIT_TIMEOUT_MS", TYPE_NUMBER, 5000)
  fetch_config_variable("CONTROLLER_USE_SSL", TYPE_BOOLEAN, true)
  fetch_config_variable("CONTROLLER_HTTP_PROXY_HOST", TYPE_STRING, "")
  fetch_config_variable("CONTROLLER_HTTP_PROXY_PORT", TYPE_NUMBER, 0)
  fetch_config_variable("CONTROLLER_HTTP_PROXY_USERNAME", TYPE_SECRET_STRING, "")
  fetch_config_variable("CONTROLLER_HTTP_PROXY_PASSWORD", TYPE_SECRET_STRING, "")
  -- fixme: Currently, the plugin never shuts down orderly - atexit handler would be needed.  Thus, the metrics
  -- collected in the agent are lost when Kong is stopped or the worker exits for whatever reason.
  fetch_config_variable("FLUSH_METRICS_ON_SHUTDOWN", TYPE_BOOLEAN, true)
  fetch_config_variable("CONTROLLER_CERTIFICATE_FILE", TYPE_STRING, "")
  fetch_config_variable("CONTROLLER_CERTIFICATE_DIR", TYPE_STRING, "")
end


-- If the SDK cannot be initialized due to a configuration error, we're not going to do any further AppDynamics SDK calls.
local sdk_initialized = false


-- Initializes the AppDynamics background threads. This is a blocking call!!
local function appd_sdk_initialize()
  local appd_conf = appd.appd_config_init()

  appd.appd_config_set_logging_min_level(appd_conf, envs.LOGGING_LEVEL)
  appd.appd_config_set_logging_log_dir(appd_conf, envs.LOGGING_LOG_DIR)

  appd.appd_config_set_controller_certificate_dir(appd_conf, envs.CONTROLLER_CERTIFICATE_DIR)
  appd.appd_config_set_controller_certificate_file(appd_conf, envs.CONTROLLER_CERTIFICATE_FILE)

  appd.appd_config_set_controller_host(appd_conf, envs.CONTROLLER_HOST)
  appd.appd_config_set_controller_port(appd_conf, envs.CONTROLLER_PORT)
  appd.appd_config_set_controller_account(appd_conf, envs.CONTROLLER_ACCOUNT)
  appd.appd_config_set_controller_access_key(appd_conf, envs.CONTROLLER_ACCESS_KEY)
  appd.appd_config_set_controller_use_ssl(appd_conf, envs.CONTROLLER_USE_SSL and 1 or 0)
  appd.appd_config_set_init_timeout_ms(appd_conf, envs.INIT_TIMEOUT_MS)

  appd.appd_config_set_app_name(appd_conf, envs.APP_NAME)
  appd.appd_config_set_tier_name(appd_conf, envs.TIER_NAME)
  appd.appd_config_set_node_name(appd_conf, envs.NODE_NAME .. "." .. ngx.worker.id())

  appd.appd_config_set_flush_metrics_on_shutdown(appd_conf, envs.FLUSH_METRICS_ON_SHUTDOWN and 1 or 0)

  if envs.CONTROLLER_HTTP_PROXY_HOST ~= "" then
    kong.log.debug('setting up proxy')
    appd.appd_config_set_controller_http_proxy_host(appd_conf, envs.CONTROLLER_HTTP_PROXY_HOST)
    appd.appd_config_set_controller_http_proxy_port(appd_conf, envs.CONTROLLER_HTTP_PROXY_PORT)
    if envs.CONTROLLER_HTTP_PROXY_USERNAME ~= "" then
      appd.appd_config_set_controller_http_proxy_username(appd_conf, envs.CONTROLLER_HTTP_PROXY_USERNAME)
      appd.appd_config_set_controller_http_proxy_password(appd_conf, envs.CONTROLLER_HTTP_PROXY_PASSWORD)
    end
  end

  kong.log.debug("Initializing SDK")
  local result = appd.appd_sdk_init(appd_conf)
  kong.log.debug("SDK Initialization returned, result " .. tostring(result))
  if result == 0 then
    kong.log.info("AppDynamics SDK initialized")
    sdk_initialized = true
  else
    kong.log.err("AppDynamics SDK initialization failed - Please ensure that all required environment variables are set")
  end
end


-- Local function to add appd exit call, returns AppDynamics generated singularity header
-- to pass it upstream in order to wrap into single business transaction.
-- @param bt_handle the business transaction handle
-- @param backend_name (string) the back end name to add to the transaction
-- @return header value, or nil+err
local function appd_make_exit_call(bt_handle, backend_name)
  local exit_handle = appd.appd_exitcall_begin(bt_handle, backend_name)
  if exit_handle == nil then
    return nil, "AppDynamics SDK call appd_exitcall_begin failed, check appd logs"
  end

  local appd_singularity_header = appd.appd_exitcall_get_correlation_header(exit_handle) -- doesn't fail
  appd.appd_exitcall_end(exit_handle)

  return ffi.string(appd_singularity_header)
end


-- Setup AppDynamics backend.
-- @return true on success, or nil+err otherwise
local function appd_setup_http_backend(backend_name, host_name)
  appd.appd_backend_declare("HTTP", backend_name)

  -- TODO: Extend this to add more properties for backend ie. appd_backend_set_identifying_property
  local rc = appd.appd_backend_set_identifying_property(backend_name, "HOST", host_name)
  if rc ~= 0 then
    return nil, "AppDynamics SDK call appd_backend_set_identifying_property failed, check appd logs"
  end

  -- add the backend
  rc = appd.appd_backend_add(backend_name)
  if rc ~= 0 then
    return nil, "ApAppDynamicspD SDK call appd_backend_add failed, check appd logs"
  end

  return true
end


function AppDynamicsHandler:init_worker()
  kong.log.debug("AppDynamicsHandler: worker " .. ngx.worker.id() .. " initializing")
  if appd then
     appd_sdk_initialize()
  end
end


-- `backends` contains a list of the backend names that were registered with the AppDynamics API.  Entries are never
-- deleted from this table, but the number of backends is assumed to be small enough for this not to cause a
-- problem.
local backends = {}

-- `controller_connection_established` is set to true if business transactions can be sent to the AppDynamics controller.
-- When we detect that the connection is not present, we set this flag to `false` and log a message.  Once the
-- connection is sensed to be present again, another message is logged and the flag is set to true.  This prevents
-- the log from being flooded with messages indicating that the AppDynamics controller is unreachable.
local controller_connection_established = false

-- runs in the 'access_by_lua_block'
function AppDynamicsHandler:access()
  if not sdk_initialized then
    return
  end

  local backend_name = "NO_SERVICE_NO_ROUTE_BACKEND"
  local backend_host = "NO_SERVICE_NO_ROUTE_BACKEND_HOST"
  local bt_name = "NO_SERVICE_NO_ROUTE_BT"

  local kong_service = get_service()
  local kong_route = get_route()

  -- Work out the AppDynamics backend name, host and business
  -- transaction based on existence of Service and Route.  We prefer
  -- the service over the route for naming the backend and the
  -- business transaction to avoid overflowing the maximum number of
  -- business transactions and backends that can exist in AppDynamics.
  -- Only for routes that don't have a service do we fall back to the
  -- route for BT and backend naming.
  if kong_service then
    local id = kong_service.name or kong_service.host
    backend_name = id
    backend_host = kong_service.host
    bt_name = id
  elseif kong_route then
    local id = kong_route.name or kong_route.id
    backend_name = id
    backend_host = id
    bt_name = id
  end

  if not backends[backend_name] then
    -- Registering backend to AppDynamics flowmap
    local ok, err = appd_setup_http_backend(backend_name, backend_host)
    if not ok then
      kong.log.err(err)
    end
    backends[backend_name] = true
  end

  -- retrieve incoming header if given
  local existing_singularity_header = get_header(APPD_SINGULARITY_HEADER)
  kong.log.debug("Singularity header incoming: ", existing_singularity_header or "NOT_FOUND")

  -- create bt-handle and set context
  local bt_handle = appd.appd_bt_begin(bt_name, existing_singularity_header)
  if bt_handle ~= nil then
    if not controller_connection_established then
      kong.log.err("Connection to AppDynamics controller established")
      controller_connection_established = true
    end

    -- create and set outgoing header
    local singularity_header = appd_make_exit_call(bt_handle, backend_name)
    kong.service.request.set_header(APPD_SINGULARITY_HEADER, singularity_header)

    -- Save plugin context for processing in log() method
    kong.ctx.plugin.appd = {
      start_time = ngx.time(),
      bt_name = bt_name,
      singularity_header = singularity_header,
      bt_handle = bt_handle,
    }

    kong.log.debug("Started business transaction, singularity header " .. singularity_header)

  else
    if controller_connection_established then
      kong.log.err("No connection to AppDynamics controller, business transaction not logged")
      controller_connection_established = false
    end
  end
end


-- Ending the BT post sending the last response byte
function AppDynamicsHandler:log()
  if not sdk_initialized then
    return
  end

  local context = kong.ctx.plugin.appd
  kong.ctx.plugin.appd = nil

  if context == nil then
    kong.log.debug("Request not traced")
    return
  end

  kong.log.debug("Ending business transaction")
  local bt_handle = context.bt_handle

  -- If the BT was started more than APPD_SDK_BT_TIMEOUT seconds ago, the SDK itself will have purged
  -- it.  To work around this, we're restarting and backdating the transaction in that case.
  local now = ngx.time()
  if now - context.start_time > APPD_SDK_BT_TIMEOUT then
    kong.log.debug("Restarting old BT due to presumed SDK timeout")
    appd.appd_bt_add_error(bt_handle, appd.APPD_LEVEL_ERROR, "Restarting long BT to work around SDK-level expiry", 1)
    bt_handle = appd.appd_bt_begin(context.bt_name, context.singularity_header)
    if bt_handle == nil then
      kong.log.err("Cannot restart old BT, please check the AppDynamics SDK logs")
      return
    end
    appd.appd_bt_enable_snapshot(bt_handle)
    appd.appd_bt_override_start_time_ms(bt_handle, context.start_time * 1000)
    appd.appd_bt_override_time_ms(bt_handle, (now - context.start_time) * 1000)
  end

  -- Adding any error to BT if API returns >= 400
  local response_status = kong.response.get_status()
  if response_status >= 400 then
    appd.appd_bt_enable_snapshot(bt_handle)
    appd.appd_bt_add_error(bt_handle, appd.APPD_LEVEL_ERROR, "API returned status code " .. response_status, 1)
  end

  -- Add further details if snapshot is occurring
  if appd.appd_bt_is_snapshotting(bt_handle) ~= 0 then
    appd.appd_bt_add_user_data(bt_handle, "route", get_route().name)
    appd.appd_bt_set_url(
      bt_handle,
      kong.request.get_scheme() .. "://" .. kong.request.get_host() .. kong.request.get_path())
  end

  appd.appd_bt_end(bt_handle)  -- end the transaction
end


-- return Appd plugin object
return AppDynamicsHandler

