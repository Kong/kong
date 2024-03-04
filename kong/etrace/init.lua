local req_dyn_hook = require("kong.dynamic_hook")
local kproto_trace = require("resty.kong.kproto.trace")
local kproto_metric = require("resty.kong.kproto.metric")
local kproto_log = require("resty.kong.kproto.log")
local errlog = require "ngx.errlog"
local http = require "resty.http"

local ngx_var = ngx.var
local ngx_timer_at = ngx.timer.at
local ngx_worker_exiting = ngx.worker.exiting
local ngx_sleep = ngx.sleep

local math_random = math.random

local ngx_get_phase = ngx.get_phase
local ngx_req_get_method = ngx.req.get_method
local ngx_req_http_version = ngx.req.http_version

local request_id_get = require ("kong.tracing.request_id").get

local trace_new = kproto_trace.new
local trace_get_serialized = kproto_trace.get_serialized
local trace_enter_span = kproto_trace.enter_span
local trace_exit_span = kproto_trace.exit_span
local trace_add_string_attribute = kproto_trace.add_string_attribute
local trace_add_bool_attribute = kproto_trace.add_bool_attribute
local trace_add_int64_attribute = kproto_trace.add_int64_attribute
local trace_add_double_attribute = kproto_trace.add_double_attribute

local metric_new = kproto_metric.new
local metric_get_serialized = kproto_metric.get_serialized
local metric_add_gauge = kproto_metric.add_gauge
local metric_add_sum = kproto_metric.add_sum

local log_new = kproto_log.new
local log_get_serialized = kproto_log.get_serialized
local log_add_info = kproto_log.add_info
local log_add_warn = kproto_log.add_warn
local log_add_error = kproto_log.add_error
local log_add_fatal = kproto_log.add_fatal

local trace_otlp_client
local metric_otlp_client
local log_otlp_client

local trace_queue = require("kong.etrace.queue").new(1024)

local TRCCE_CONNECT_OPTS = {
    scheme = "http",
    host = "localhost",
    pool = "qiqi-demo-trace",
    pool_size = 4096,
    port = 5000,
}

local METRIC_CONNECT_OPTS = {
    scheme = "http",
    host = "localhost",
    pool = "qiqi-demo-metric",
    pool_size = 16,
    port = 5000,
}

local LOG_CONNECT_OPTS = {
    scheme = "http",
    host = "localhost",
    pool = "qiqi-demo-log",
    pool_size = 16,
    port = 5000,
}

local TRACE_REQ_PARAMS = {
    -- version = "1.1",
    method = "POST",
    path = "/v1/traces",
    query = "",
    headers = {
        ["Content-Type"] = "application/x-protobuf",
        ["Content-Length"] = nil,
    },
    body = nil
}

local METRIC_REQ_PARAMS = {
    -- version = "1.1",
    method = "POST",
    path = "/v1/metrics",
    query = "",
    headers = {
        ["Content-Type"] = "application/x-protobuf",
        ["Content-Length"] = nil,
    },
    body = nil
}

local LOG_REQ_PARAMS = {
    -- version = "1.1",
    method = "POST",
    path = "/v1/logs",
    query = "",
    headers = {
        ["Content-Type"] = "application/x-protobuf",
        ["Content-Length"] = nil,
    },
    body = nil
}


local sampling_rate

local _M = {}

local VALID_PHASES = {
    rewrite       = true,
    balancer      = true,
    access        = true,
    header_filter = true,
    body_filter   = true,
    log           = true,
}

local ADD_LOG_FUNC = {
    [ngx.DEBUG] = log_add_info,
    [ngx.INFO] = log_add_info,
    [ngx.NOTICE] = log_add_info,
    [ngx.WARN] = log_add_warn,
    [ngx.ERR] = log_add_error,
    [ngx.CRIT] = log_add_fatal,
    [ngx.ALERT] = log_add_fatal,
    [ngx.EMERG] = log_add_fatal,
}


local function otlp_trace_cb(premature, buf)
    if premature then
        return
    end

    local httpc = http.new()

    assert(httpc:connect(TRCCE_CONNECT_OPTS))

    local res = assert(httpc:request({
        method = "POST",
        path = "/v1/traces",
        query = "",
        headers = {
            ["Content-Type"] = "application/x-protobuf",
            ["Content-Length"] = #buf,
        },
        body = buf
    }))

    if res.has_body then
        res:read_body()
        res:read_trailers()
    end

    if res.status ~= 200 and res.status ~= 201 then
        ngx.log(ngx.ERR, "failed to send trace: ", res.status, " ", res.body)
    end

    httpc:set_keepalive(9999999)
end


local function otlp_metric_cb(premature)
    if premature then
        return
    end

    local httpc = http.new()
    assert(httpc:connect(METRIC_CONNECT_OPTS))

    local metrics = metric_new()

    local nginx_statistics = kong.nginx.get_statistics()

    local total_requests = nginx_statistics['total_requests']
    metric_add_gauge(metrics, "kong_total_requests", total_requests)

    local nginx_connections_active = nginx_statistics['connections_active']
    local nginx_connections_reading = nginx_statistics['connections_reading']
    local nginx_connections_writing = nginx_statistics['connections_writing']
    local nginx_connections_waiting = nginx_statistics['connections_waiting']
    local nginx_connections_accepted = nginx_statistics['connections_accepted']
    local nginx_connections_handled = nginx_statistics['connections_handled']

    metric_add_gauge(metrics, "nginx_connections_active", nginx_connections_active)
    metric_add_gauge(metrics, "nginx_connections_reading", nginx_connections_reading)
    metric_add_gauge(metrics, "nginx_connections_writing", nginx_connections_writing)
    metric_add_gauge(metrics, "nginx_connections_waiting", nginx_connections_waiting)
    metric_add_gauge(metrics, "nginx_connections_accepted", nginx_connections_accepted)
    metric_add_gauge(metrics, "nginx_connections_handled", nginx_connections_handled)

    local pending_timers = ngx.timer.pending_count()
    metric_add_gauge(metrics, "nginx_pending_timers", pending_timers)

    local running_timers = ngx.timer.running_count()
    metric_add_gauge(metrics, "nginx_running_timers", running_timers)

    -- local request_latency = message.latencies.request
    -- metric_add_gauge(metrics, "kong_request_latency", request_latency)

    local gcsize = collectgarbage("count")
    metric_add_gauge(metrics, "lua_vm_size", gcsize)

    local buf = metric_get_serialized(metrics)

    METRIC_REQ_PARAMS.body = buf
    METRIC_REQ_PARAMS.headers["Content-Length"] = #buf
    local res = assert(httpc:request(METRIC_REQ_PARAMS))
    METRIC_REQ_PARAMS.body = nil

    if res.has_body then
        res:read_body()
        res:read_trailers()
    end

    if res.status ~= 200 and res.status ~= 201 then
        ngx.log(ngx.ERR, "failed to send metrics: ", res.status, " ", res.body)
    end

    httpc:set_keepalive(9999999)
end


local function otlp_log_cb(premature)
    if premature then
        return
    end

    local httpc = http.new()
    assert(httpc:connect(LOG_CONNECT_OPTS))

    local raw_logs = assert(errlog.get_logs(64))
    local logs = log_new()

    for i = 1, #raw_logs, 3 do
        local level = raw_logs[i]
        local time = (assert(tonumber(raw_logs[i + 1]))) * 1000000000
        local msg = raw_logs[i + 2]

        ADD_LOG_FUNC[level](logs, time, msg)
    end

    local buf = log_get_serialized(logs)

    LOG_REQ_PARAMS.body = buf
    LOG_REQ_PARAMS.headers["Content-Length"] = #buf
    local res, err = httpc:request(LOG_REQ_PARAMS)
    LOG_REQ_PARAMS.body = nil

    if res.has_body then
        res:read_body()
        res:read_trailers()
    end

    if res.status ~= 200 and res.status ~= 201 then
        ngx.log(ngx.ERR, "failed to send logs: ", res.status, " ", res.body)
    end

    httpc:set_keepalive(9999999)
end


function _M.globalpatches()
    require("kong.etrace.hooks").globalpatches(_M)

    req_dyn_hook.hook("etrace", "before:rewrite", function(ctx)
        if math_random() > sampling_rate then
            return
        end

        local tr = trace_new()
        ctx.tr = tr

        local client = kong.client
        local scheme = ctx.scheme or ngx_var.scheme
        local host = ngx_var.host
        local request_uri = scheme .. "://" .. host .. (ctx.request_uri or ngx_var.request_uri)

        trace_enter_span(tr, "Kong")
        trace_add_string_attribute(tr, "http.method", ngx_req_get_method())
        trace_add_string_attribute(tr, "http.url", request_uri)
        trace_add_string_attribute(tr, "http.host", host)
        trace_add_string_attribute(tr, "http.scheme", scheme)
        trace_add_int64_attribute(tr, "http.flavor", ngx_req_http_version())
        trace_add_string_attribute(tr, "http.client_ip", client.get_forwarded_ip())
        trace_add_string_attribute(tr, "net.peer.ip", client.get_ip())
        trace_add_string_attribute(tr, "kong.request.id", request_id_get())

        trace_enter_span(tr, "rewrite")
    end)

    req_dyn_hook.hook("etrace", "after:rewrite", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr) -- rewrite
    end)

    req_dyn_hook.hook("etrace", "before:balancer", function(ctx)
        if not ctx.tr then
            return
        end

        trace_enter_span(ctx.tr, "balancer")
    end)

    req_dyn_hook.hook("etrace", "after:balancer", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr)

        trace_enter_span(ctx.tr, "Upstream (Time to first byte)")
    end)

    req_dyn_hook.hook("etrace", "before:access", function(ctx)
        if not ctx.tr then
            return
        end

        trace_enter_span(ctx.tr, "access")
    end)

    req_dyn_hook.hook("etrace", "after:access", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr)
    end)

    req_dyn_hook.hook("etrace", "before:response", function(ctx)
        if not ctx.tr then
            return
        end

        trace_enter_span(ctx.tr, "response")
    end)

    req_dyn_hook.hook("etrace", "after:response", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr)
    end)

    req_dyn_hook.hook("etrace", "before:header_filter", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr) -- Upstream (Time to first byte)

        trace_enter_span(ctx.tr, "header_filter")
        trace_add_string_attribute(ctx.tr, "http.status_code", tostring(ngx.status))
        local r = ngx.ctx.route
        trace_add_string_attribute(ctx.tr, "http.route", r and r.paths and r.paths[1] or "")
    end)

    req_dyn_hook.hook("etrace", "after:header_filter", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr)

        trace_enter_span(ctx.tr, "Upstream (Streaming)")
    end)

    req_dyn_hook.hook("etrace", "before:body_filter", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr) -- Upstream (Streaming)

        trace_enter_span(ctx.tr, "body_filter")
    end)

    req_dyn_hook.hook("etrace", "after:body_filter", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr)

        trace_enter_span(ctx.tr, "Upstream (Streaming)")
    end)

    req_dyn_hook.hook("etrace", "before:log", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr) -- Upstream (Streaming)

        trace_enter_span(ctx.tr, "log")
    end)

    req_dyn_hook.hook("etrace", "after:log", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr) -- log
        trace_exit_span(ctx.tr) -- Kong

        local serialized_data = assert(trace_get_serialized(ctx.tr))
        -- local fp = assert(io.open("/tmp/etrace.bin", "w"))
        -- assert(fp:write(serialized_data))
        -- assert(fp:close())

        ngx_timer_at(0, otlp_trace_cb, serialized_data)

        -- if trace_queue:length() >= 500000 then
        --     ngx.log(ngx.ERR, "trace queue is full")
        --     return
        -- end

        -- trace_queue:push_right(serialized_data)
    end)

    req_dyn_hook.hook("etrace", "before:plugin_iterator", function(ctx)
        if not ctx.tr then
            return
        end

        trace_enter_span(assert(ctx.tr), "plugins")
    end)

    req_dyn_hook.hook("etrace", "after:plugin_iterator", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(assert(ctx.tr)) -- plugins
    end)

    req_dyn_hook.hook("etrace", "before:a_plugin", function(ctx, plugin_name, plugin_id)
        if not ctx.tr then
            return
        end

        trace_enter_span(assert(ctx.tr), plugin_name)
        trace_add_string_attribute(ctx.tr, "plugin_id", plugin_id)
    end)

    req_dyn_hook.hook("etrace", "after:a_plugin", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(assert(ctx.tr)) -- plugin_name
    end)

    req_dyn_hook.hook("etrace", "before:router", function(ctx)
        if not ctx.tr then
            return
        end

        trace_enter_span(ctx.tr, "router")
    end)

    req_dyn_hook.hook("etrace", "after:router", function(ctx)
        if not ctx.tr then
            return
        end

        trace_exit_span(ctx.tr)
    end)
end


function _M.init(kong_config)
    sampling_rate = tonumber(kong_config.tracing_sampling_rate) or 1
    assert(type(sampling_rate) == "number" and sampling_rate >= 0 and sampling_rate <= 1, "invalid tracing_sampling_rate")
    ngx.log(ngx.ERR, "etrace init: sampling_rate=", sampling_rate)
end


function _M.init_worker()
    req_dyn_hook.always_enable("etrace")
    ngx.log(ngx.ERR, "etrace init_worker")

    -- ngx.timer.at(0, otlp_trace_cb)
    ngx.timer.every(30, otlp_metric_cb)
    ngx.timer.every(30, otlp_log_cb)
end


function _M.enter_span(name)
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    trace_enter_span(tr, name)
end


function _M.add_string_attribute(key, value)
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    trace_add_string_attribute(tr, key, value)
end


function _M.add_bool_attribute(key, value)
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    trace_add_bool_attribute(tr, key, value)
end


function _M.add_int64_attribute(key, value)
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    trace_add_int64_attribute(tr, key, value)
end


function _M.add_double_attribute(key, value)
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    trace_add_double_attribute(tr, key, value)
end


function _M.exit_span()
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    trace_exit_span(tr)
end


return _M
