-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- AppDynamics FFI bindings
local ffi = require "ffi"

ffi.cdef [[
typedef void* appd_bt_handle;
typedef void* appd_exitcall_handle;
typedef void* appd_frame_handle;
typedef void* appd_event_handle;
struct appd_config;
struct appd_context_config;
enum appd_config_log_level
{
	APPD_LOG_LEVEL_TRACE,
	APPD_LOG_LEVEL_DEBUG,
	APPD_LOG_LEVEL_INFO,
	APPD_LOG_LEVEL_WARN,
	APPD_LOG_LEVEL_ERROR,
	APPD_LOG_LEVEL_FATAL
};
enum appd_error_level
{
  APPD_LEVEL_NOTICE,
  APPD_LEVEL_WARNING,
  APPD_LEVEL_ERROR
};

struct appd_config* appd_config_init();

void appd_config_set_app_name(struct appd_config* cfg, const char* app);
void appd_config_set_tier_name(struct appd_config* cfg, const char* tier);
void appd_config_set_node_name(struct appd_config* cfg, const char* node);
void appd_config_set_controller_host(struct appd_config* cfg, const char* host);
void appd_config_set_controller_port(struct appd_config* cfg, const unsigned short port);
void appd_config_set_controller_account(struct appd_config* cfg, const char* acct);
void appd_config_set_controller_access_key(struct appd_config* cfg, const char* key);
void appd_config_set_controller_use_ssl(struct appd_config* cfg, const unsigned int ssl);
void appd_config_set_logging_min_level(struct appd_config* cfg, enum appd_config_log_level lvl);
void appd_config_set_init_timeout_ms(struct appd_config* cfg, const int time);
void appd_config_set_flush_metrics_on_shutdown(struct appd_config* cfg, int enable);
void appd_config_set_logging_log_dir(struct appd_config* cfg, const char* dir);

void appd_config_set_controller_certificate_file(struct appd_config* cfg, const char* file);
void appd_config_set_controller_certificate_dir(struct appd_config* cfg, const char* dir);

void appd_config_set_controller_http_proxy_host(struct appd_config* cfg, const char* host);
void appd_config_set_controller_http_proxy_port(struct appd_config* cfg,const unsigned short port);
void appd_config_set_controller_http_proxy_username(struct appd_config* cfg,const char* user);
void appd_config_set_controller_http_proxy_password(struct appd_config* cfg,const char* pwd);
void appd_config_getenv(struct appd_config* cfg, const char* prefix);


int appd_sdk_init(const struct appd_config* config);

void appd_backend_declare(const char* type, const char* unregistered_name);
int appd_backend_set_identifying_property(const char* backend, const char* key, const char* value);
int appd_backend_prevent_agent_resolution(const char* backend);
int appd_backend_add(const char* backend);

appd_exitcall_handle appd_exitcall_begin(appd_bt_handle bt, const char* backend);
const char* appd_exitcall_get_correlation_header(appd_exitcall_handle exitcall);
void appd_exitcall_end(appd_exitcall_handle exitcall);


appd_bt_handle appd_bt_begin(const char* name, const char* correlation_header);
void appd_bt_store(appd_bt_handle bt, const char* guid);
appd_bt_handle appd_bt_get(const char* guid);
void appd_bt_end(appd_bt_handle bt);

void appd_sdk_term();

void appd_bt_add_user_data(appd_bt_handle bt, const char* key, const char* value);
void appd_bt_set_url(appd_bt_handle bt, const char* url);
int appd_bt_enable_snapshot(appd_bt_handle bt);
int appd_bt_is_snapshotting(appd_bt_handle  bt);
void appd_bt_add_error (appd_bt_handle  bt, enum appd_error_level  level, const char *  message, int  mark_bt_as_error);
void appd_bt_override_start_time_ms(appd_bt_handle bt, int64_t timeMS);
void appd_bt_override_time_ms(appd_bt_handle bt, int64_t timeMS);
]]

local appdynamics = ffi.load("appdynamics")

-- pthread might be in different locations, so try in turn
local ok, err1 = pcall(ffi.load, "pthread", true)
if not ok then
  local err2
  ok, err2 = pcall(ffi.load, "libpthread.so.0", true)
  if not ok then
    kong.log.err(err1)
    kong.log.err(err2)
    return error("failed to load a suitable pthread lib")
  end
end

return appdynamics

