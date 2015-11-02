-- Copyright (C) 2013-2014 Jiale Zhi (calio), CloudFlare Inc.
--require "luacov"

local concat                = table.concat
local tcp                   = ngx.socket.tcp
local timer_at              = ngx.timer.at
local ngx_log               = ngx.log
local ngx_sleep             = ngx.sleep
local type                  = type
local pairs                 = pairs
local tostring              = tostring
local debug                 = ngx.config.debug

local DEBUG                 = ngx.DEBUG
local CRIT                  = ngx.CRIT

local MAX_PORT              = 65535


-- table.new(narr, nrec)
local succ, new_tab = pcall(require, "table.new")
if not succ then
    new_tab = function () return {} end
end

local _M = new_tab(0, 5)

local is_exiting

if not ngx.config or not ngx.config.ngx_lua_version
    or ngx.config.ngx_lua_version < 9003 then

    is_exiting = function() return false end

    ngx_log(CRIT, "We strongly recommend you to update your ngx_lua module to "
            .. "0.9.3 or above. lua-resty-logger-socket will lose some log "
            .. "messages when Nginx reloads if it works with ngx_lua module "
            .. "below 0.9.3")
else
    is_exiting = ngx.worker.exiting
end


_M._VERSION = '0.03'

-- user config
local flush_limit           = 4096         -- 4KB
local drop_limit            = 1048576      -- 1MB
local timeout               = 1000         -- 1 sec
local host
local port
local ssl                   = false
local ssl_verify            = true
local sni_host
local path
local max_buffer_reuse      = 10000        -- reuse buffer for at most 10000
                                           -- times
local periodic_flush        = nil
local need_periodic_flush   = nil

-- internal variables
local buffer_size           = 0
-- 2nd level buffer, it stores logs ready to be sent out
local send_buffer           = ""
-- 1st level buffer, it stores incoming logs
local log_buffer_data       = new_tab(20000, 0)
-- number of log lines in current 1st level buffer, starts from 0
local log_buffer_index      = 0

local last_error

local connecting
local connected
local exiting
local retry_connect         = 0
local retry_send            = 0
local max_retry_times       = 3
local retry_interval        = 100         -- 0.1s
local pool_size             = 10
local flushing
local logger_initted
local counter               = 0
local ssl_session

local function _write_error(msg)
    last_error = msg
end

local function _do_connect()
    local ok, err, sock

    if not connected then
        sock, err = tcp()
        if not sock then
            _write_error(err)
            return nil, err
        end

        sock:settimeout(timeout)
    end

    -- "host"/"port" and "path" have already been checked in init()
    if host and port then
        ok, err =  sock:connect(host, port)
    elseif path then
        ok, err =  sock:connect("unix:" .. path)
    end

    if not ok then
        return nil, err
    end

    return sock
end

local function _do_handshake(sock)
    if not ssl then
        return sock
    end

    local session, err = sock:sslhandshake(ssl_session, sni_host or host,
                                           ssl_verify)
    if not session then
        return nil, err
    end

    ssl_session = session
    return sock
end

local function _connect()
    local err, sock

    if connecting then
        if debug then
            ngx_log(DEBUG, "previous connection not finished")
        end
        return nil, "previous connection not finished"
    end

    connected = false
    connecting = true

    retry_connect = 0

    while retry_connect <= max_retry_times do
        sock, err = _do_connect()

        if sock then
            sock, err = _do_handshake(sock)
            if sock then
                connected = true
                break
            end
        end

        if debug then
            ngx_log(DEBUG, "reconnect to the log server: ", err)
        end

        -- ngx.sleep time is in seconds
        if not exiting then
            ngx_sleep(retry_interval / 1000)
        end

        retry_connect = retry_connect + 1
    end

    connecting = false
    if not connected then
        return nil, "try to connect to the log server failed after "
                    .. max_retry_times .. " retries: " .. err
    end

    return sock
end

local function _prepare_stream_buffer()
    local packet = concat(log_buffer_data, "", 1, log_buffer_index)
    send_buffer = send_buffer .. packet

    log_buffer_index = 0
    counter = counter + 1
    if counter > max_buffer_reuse then
        log_buffer_data = new_tab(20000, 0)
        counter = 0
        if debug then
            ngx_log(DEBUG, "log buffer reuse limit (" .. max_buffer_reuse
                    .. ") reached, create a new \"log_buffer_data\"")
        end
    end
end

local function _do_flush()
    local ok, err, sock, bytes
    local packet = send_buffer

    sock, err = _connect()
    if not sock then
        return nil, err
    end

    bytes, err = sock:send(packet)
    if not bytes then
        -- "sock:send" always closes current connection on error
        return nil, err
    end

    if debug then
        ngx.update_time()
        ngx_log(DEBUG, ngx.now(), ":log flush:" .. bytes .. ":" .. packet)
    end

    ok, err = sock:setkeepalive(0, pool_size)
    if not ok then
        return nil, err
    end

    return bytes
end

local function _need_flush()
    if buffer_size > 0 then
        return true
    end

    return false
end

local function _flush_lock()
    if not flushing then
        if debug then
            ngx_log(DEBUG, "flush lock acquired")
        end
        flushing = true
        return true
    end
    return false
end

local function _flush_unlock()
    if debug then
        ngx_log(DEBUG, "flush lock released")
    end
    flushing = false
end

local function _flush()
    local err

    -- pre check
    if not _flush_lock() then
        if debug then
            ngx_log(DEBUG, "previous flush not finished")
        end
        -- do this later
        return true
    end

    if not _need_flush() then
        if debug then
            ngx_log(DEBUG, "no need to flush:", log_buffer_index)
        end
        _flush_unlock()
        return true
    end

    -- start flushing
    retry_send = 0
    if debug then
        ngx_log(DEBUG, "start flushing")
    end

    local bytes
    while retry_send <= max_retry_times do
        if log_buffer_index > 0 then
            _prepare_stream_buffer()
        end

        bytes, err = _do_flush()

        if bytes then
            break
        end

        if debug then
            ngx_log(DEBUG, "resend log messages to the log server: ", err)
        end

        -- ngx.sleep time is in seconds
        if not exiting then
            ngx_sleep(retry_interval / 1000)
        end

        retry_send = retry_send + 1
    end

    _flush_unlock()

    if not bytes then
        local err_msg = "try to send log messages to the log server "
                        .. "failed after " .. max_retry_times .. " retries: "
                        .. err
        _write_error(err_msg)
        return nil, err_msg
    else
        if debug then
            ngx_log(DEBUG, "send " .. bytes .. " bytes")
        end
    end

    buffer_size = buffer_size - #send_buffer
    send_buffer = ""

    return bytes
end

local function _periodic_flush()
    if need_periodic_flush then
        -- no regular flush happened after periodic flush timer had been set
        if debug then
            ngx_log(DEBUG, "performing periodic flush")
        end
        _flush()
    else
        if debug then
            ngx_log(DEBUG, "no need to perform periodic flush: regular flush "
                    .. "happened before")
        end
        need_periodic_flush = true
    end

    timer_at(periodic_flush, _periodic_flush)
end

local function _flush_buffer()
    local ok, err = timer_at(0, _flush)

    need_periodic_flush = false

    if not ok then
        _write_error(err)
        return nil, err
    end
end

local function _write_buffer(msg)
    log_buffer_index = log_buffer_index + 1
    log_buffer_data[log_buffer_index] = msg

    buffer_size = buffer_size + #msg


    return buffer_size
end

function _M.init(user_config)
    if (type(user_config) ~= "table") then
        return nil, "user_config must be a table"
    end

    for k, v in pairs(user_config) do
        if k == "host" then
            if type(v) ~= "string" then
                return nil, '"host" must be a string'
            end
            host = v
        elseif k == "port" then
            if type(v) ~= "number" then
                return nil, '"port" must be a number'
            end
            if v < 0 or v > MAX_PORT then
                return nil, ('"port" out of range 0~%s'):format(MAX_PORT)
            end
            port = v
        elseif k == "path" then
            if type(v) ~= "string" then
                return nil, '"path" must be a string'
            end
            path = v
        elseif k == "flush_limit" then
            if type(v) ~= "number" or v < 0 then
                return nil, 'invalid "flush_limit"'
            end
            flush_limit = v
        elseif k == "drop_limit" then
            if type(v) ~= "number" or v < 0 then
                return nil, 'invalid "drop_limit"'
            end
            drop_limit = v
        elseif k == "timeout" then
            if type(v) ~= "number" or v < 0 then
                return nil, 'invalid "timeout"'
            end
            timeout = v
        elseif k == "max_retry_times" then
            if type(v) ~= "number" or v < 0 then
                return nil, 'invalid "max_retry_times"'
            end
            max_retry_times = v
        elseif k == "retry_interval" then
            if type(v) ~= "number" or v < 0 then
                return nil, 'invalid "retry_interval"'
            end
            -- ngx.sleep time is in seconds
            retry_interval = v
        elseif k == "pool_size" then
            if type(v) ~= "number" or v < 0 then
                return nil, 'invalid "pool_size"'
            end
            pool_size = v
        elseif k == "max_buffer_reuse" then
            if type(v) ~= "number" or v < 0 then
                return nil, 'invalid "max_buffer_reuse"'
            end
            max_buffer_reuse = v
        elseif k == "periodic_flush" then
            if type(v) ~= "number" or v < 0 then
                return nil, 'invalid "periodic_flush"'
            end
            periodic_flush = v
        elseif k == "ssl" then
            if type(v) ~= "boolean" then
                return nil, '"ssl" must be a boolean value'
            end
            ssl = v
        elseif k == "ssl_verify" then
            if type(v) ~= "boolean" then
                return nil, '"ssl_verify" must be a boolean value'
            end
            ssl_verify = v
        elseif k == "sni_host" then
            if type(v) ~= "string" then
                return nil, '"sni_host" must be a string'
            end
            sni_host = v
        end
    end

    if not (host and port) and not path then
        return nil, "no logging server configured. \"host\"/\"port\" or "
                .. "\"path\" is required."
    end


    if (flush_limit >= drop_limit) then
        return nil, "\"flush_limit\" should be < \"drop_limit\""
    end

    flushing = false
    exiting = false
    connecting = false

    connected = false
    retry_connect = 0
    retry_send = 0

    logger_initted = true

    if periodic_flush then
        if debug then
            ngx_log(DEBUG, "periodic flush enabled for every "
                    .. periodic_flush .. " seconds")
        end
        need_periodic_flush = true
        timer_at(periodic_flush, _periodic_flush)
    end

    return logger_initted
end

function _M.log(msg)
    if not logger_initted then
        return nil, "not initialized"
    end

    local bytes

    if type(msg) ~= "string" then
        msg = tostring(msg)
    end

    if (debug) then
        ngx.update_time()
        ngx_log(DEBUG, ngx.now(), ":log message length: " .. #msg)
    end

    local msg_len = #msg
    -- response of "_flush_buffer" is not checked, because it writes
    -- error buffer
    if (is_exiting()) then
        exiting = true
        _write_buffer(msg)
        _flush_buffer()
        if (debug) then
            ngx_log(DEBUG, "Nginx worker is exiting")
        end
        bytes = 0
    elseif (msg_len + buffer_size < flush_limit) then
        _write_buffer(msg)
        bytes = msg_len
    elseif (msg_len + buffer_size <= drop_limit) then
        _write_buffer(msg)
        _flush_buffer()
        bytes = msg_len
    else
        _flush_buffer()
        if (debug) then
            ngx_log(DEBUG, "logger buffer is full, this log message will be "
                    .. "dropped")
        end
        bytes = 0
        --- this log message doesn't fit in buffer, drop it
    end

    if last_error then
        local err = last_error
        last_error = nil
        return bytes, err
    end

    return bytes
end

function _M.initted()
    return logger_initted
end

_M.flush = _flush

return _M

