local req_dyn_hook = require("kong.dynamic_hook")
local kproto = require("resty.kong.kproto")

local ngx_var = ngx.var

local math_random = math.random

local ngx_get_phase = ngx.get_phase
local ngx_req_get_method = ngx.req.get_method
local ngx_req_http_version = ngx.req.http_version

local request_id_get = require ("kong.tracing.request_id").get

local kproto_new = kproto.new
local kproto_free = kproto.free
local kproto_enter_span = kproto.enter_span
local kproto_add_string_attribute = kproto.add_string_attribute
local kproto_add_bool_attribute = kproto.add_int64_attribute
local kproto_add_int64_attribute = kproto.add_int64_attribute
local kproto_add_double_attribute = kproto.add_double_attribute
local kproto_exit_span = kproto.exit_span
local _kproto_get_serialized = kproto.get_serialized

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


function _M.globalpatches()
    require("kong.etrace.hooks").globalpatches(_M)

    req_dyn_hook.hook("etrace", "before:rewrite", function(ctx)
        if math_random() > sampling_rate then
            return
        end

        -- ngx.log(ngx.ERR, "etrace:before:rewrite")

        local tr = kproto_new()
        ctx.tr = tr

        local client = kong.client
        local scheme = ctx.scheme or ngx_var.scheme
        local host = ngx_var.host
        local request_uri = scheme .. "://" .. host .. (ctx.request_uri or ngx_var.request_uri)

        kproto_enter_span(tr, "Kong")
        kproto_add_string_attribute(tr, "http.method", ngx_req_get_method())
        kproto_add_string_attribute(tr, "http.url", request_uri)
        kproto_add_string_attribute(tr, "http.host", host)
        kproto_add_string_attribute(tr, "http.scheme", scheme)
        kproto_add_int64_attribute(tr, "http.flavor", ngx_req_http_version())
        kproto_add_string_attribute(tr, "http.client_ip", client.get_forwarded_ip())
        kproto_add_string_attribute(tr, "net.peer.ip", client.get_ip())
        kproto_add_string_attribute(tr, "kong.request.id", request_id_get())

        kproto_enter_span(tr, "rewrite")
    end)

    req_dyn_hook.hook("etrace", "after:rewrite", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_exit_span(ctx.tr) -- rewrite
    end)

    req_dyn_hook.hook("etrace", "before:balancer", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_enter_span(ctx.tr, "balancer")
    end)

    req_dyn_hook.hook("etrace", "after:balancer", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_exit_span(ctx.tr)
    end)

    req_dyn_hook.hook("etrace", "before:access", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_enter_span(ctx.tr, "access")
    end)

    req_dyn_hook.hook("etrace", "after:access", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_exit_span(ctx.tr)
    end)

    req_dyn_hook.hook("etrace", "before:response", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_enter_span(ctx.tr, "response")
    end)

    req_dyn_hook.hook("etrace", "after:response", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_exit_span(ctx.tr)
    end)

    req_dyn_hook.hook("etrace", "before:header_filter", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_enter_span(ctx.tr, "header_filter")
        kproto_add_string_attribute(ctx.tr, "http.status_code", tostring(ngx.status))
        local r = ngx.ctx.route
        kproto_add_string_attribute(ctx.tr, "http.route", r and r.paths and r.paths[1] or "")
    end)

    req_dyn_hook.hook("etrace", "after:header_filter", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_exit_span(ctx.tr)
    end)

    req_dyn_hook.hook("etrace", "before:body_filter", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_enter_span(ctx.tr, "body_filter")
    end)

    req_dyn_hook.hook("etrace", "after:body_filter", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_exit_span(ctx.tr)
    end)

    req_dyn_hook.hook("etrace", "before:log", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_enter_span(ctx.tr, "log")
    end)

    req_dyn_hook.hook("etrace", "after:log", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_exit_span(ctx.tr) -- log
        kproto_exit_span(ctx.tr) -- Kong

        -- ngx.log(ngx.ERR, "AAAAAAAAA")

        -- local serialized_data = _kproto_get_serialized(ctx.tr)
        -- local fp = assert(io.open("/tmp/etrace.bin", "w"))
        -- assert(fp:write(serialized_data))
        -- assert(fp:close())

        -- ngx.log(ngx.ERR, "BBBBBBBBB")

        kproto_free(ctx.tr)
    end)

    req_dyn_hook.hook("etrace", "before:plugin_iterator", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_enter_span(assert(ctx.tr), "plugin_iterator")
    end)

    req_dyn_hook.hook("etrace", "after:plugin_iterator", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_exit_span(assert(ctx.tr)) -- plugin_iterator
    end)

    req_dyn_hook.hook("etrace", "before:a_plugin", function(ctx, plugin_name, plugin_id)
        if not ctx.tr then
            return
        end

        kproto_enter_span(assert(ctx.tr), plugin_name)
        kproto_add_string_attribute(ctx.tr, "plugin_id", plugin_id)
    end)

    req_dyn_hook.hook("etrace", "after:a_plugin", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_exit_span(assert(ctx.tr)) -- plugin_name
    end)

    req_dyn_hook.hook("etrace", "before:router", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_enter_span(ctx.tr, "router")
    end)

    req_dyn_hook.hook("etrace", "after:router", function(ctx)
        if not ctx.tr then
            return
        end

        kproto_exit_span(ctx.tr)
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
end


function _M.enter_span(name)
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    kproto_enter_span(tr, name)
end


function _M.add_string_attribute(key, value)
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    kproto_add_string_attribute(tr, key, value)
end


function _M.add_bool_attribute(key, value)
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    kproto_add_bool_attribute(tr, key, value)
end


function _M.add_int64_attribute(key, value)
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    kproto_add_int64_attribute(tr, key, value)
end


function _M.add_double_attribute(key, value)
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    kproto_add_double_attribute(tr, key, value)
end


function _M.exit_span()
    if not VALID_PHASES[ngx_get_phase()] then
        return
    end

    local tr = ngx.ctx.tr
    if not tr then
        return
    end

    kproto_exit_span(tr)
end


return _M
