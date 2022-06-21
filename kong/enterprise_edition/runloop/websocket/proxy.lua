-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

---
-- XXX WebSocket proxy library
--
-- Source: https://github.com/Kong/lua-resty-websocket-proxy
--
-- This has been moved in-tree temporarily so I can iterate on it more quickly
-- while working on WebSocket PDK features and such.


local new_tab = require "table.new"
local clear_tab = require "table.clear"
local ws_client = require "resty.websocket.client"
local ws_server = require "resty.websocket.server"


local type = type
local setmetatable = setmetatable
local insert = table.insert
local concat = table.concat
local yield = coroutine.yield
local co_running = coroutine.running
local fmt = string.format
local sub = string.sub
local gsub = string.gsub
local find = string.find
local log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG
local WARN = ngx.WARN
local INFO = ngx.INFO
local now = ngx.now
local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local kill = ngx.thread.kill
local max = math.max


local DEBUG_PAYLOAD_MAX_LEN = 24
local STATE = {
    INIT          = 1, -- pre-handshake
    ESTABLISHED   = 2, -- post-handshake
    CLOSING       = 3, -- peer has been sent a close frame
    CLOSED        = 4, -- peer connection is fully closed
}

local OPCODE = {
    ["continuation"] = 0x0,
    ["text"] = 0x1,
    ["binary"] = 0x2,
    ["close"] = 0x8,
    ["ping"] = 0x9,
    ["pong"] = 0xa,
}

local PEER = {
  client = "upstream",
  upstream = "client",
}

local LINGERING_TIME = 30000
local LINGERING_TIMEOUT = 5000


-- maximum allowed control frame size that the WebSocket spec allows
--
-- we shouldn't set lua-resty-websocket send/recv limits lower than this,
-- or it will interfere with sending/sending control frames
--
-- data frame limits can still be lower than this
local MIN_PAYLOAD = 125


local function new_ctx(proxy, role, ws)
    local peer = PEER[role]

    local max_recv_len = proxy[role .. "_max_frame_size"]
    if max_recv_len then
        ws.max_recv_len = max(max_recv_len, MIN_PAYLOAD)
    end

    local max_send_len = proxy[peer .. "_max_frame_size"]
    if max_send_len then
        ws.max_send_len = max(max_send_len, MIN_PAYLOAD)
    end

    return {
        role             = role,
        state            = STATE.ESTABLISHED,
        ws               = ws,
        close_sent       = nil,
        frame_buf        = new_tab(0, 0),
        max_frame_size   = max_recv_len,
        max_fragments    = proxy[role .. "_max_fragments"],
    }
end


local _M = {
    _VERSION = "0.0.1",
}


local _mt = { __index = _M }


function _M.new(opts)
    if opts == nil then
        opts = new_tab(0, 0)
    end

    if type(opts) ~= "table" then
        error("opts must be a table", 2)
    end

    if opts.on_frame ~= nil and type(opts.on_frame) ~= "function" then
        error("opts.on_frame must be a function", 2)
    end

    if opts.recv_timeout ~= nil and type(opts.recv_timeout) ~= "number" then
        error("opts.recv_timeout must be a number", 2)
    end

    if opts.send_timeout ~= nil and type(opts.send_timeout) ~= "number" then
        error("opts.send_timeout must be a number", 2)
    end

    if opts.connect_timeout ~= nil and type(opts.connect_timeout) ~= "number" then
        error("opts.connect_timeout must be a number", 2)
    end

    if opts.client_max_frame_size ~= nil
       and (type(opts.client_max_frame_size) ~= "number"
            or opts.client_max_frame_size < 1)
    then
        error("opts.client_max_frame_size must be a number >= 1", 2)
    end

    if opts.client_max_fragments ~= nil
       and (type(opts.client_max_fragments) ~= "number"
            or opts.client_max_fragments < 1)
    then
        error("opts.client_max_fragments must be a number >= 1", 2)
    end

    if opts.upstream_max_frame_size ~= nil
       and (type(opts.upstream_max_frame_size) ~= "number"
            or opts.upstream_max_frame_size < 1)
    then
        error("opts.upstream_max_frame_size must be a number >= 1", 2)
    end

    if opts.upstream_max_fragments ~= nil
       and (type(opts.upstream_max_fragments) ~= "number"
            or opts.upstream_max_fragments < 1)
    then
        error("opts.upstream_max_fragments must be a number >= 1", 2)
    end

    if opts.lingering_timeout ~= nil and type(opts.lingering_timeout) ~= "number" then
        error("opts.lingering_timeout must be a number", 2)
    end

    if opts.lingering_time ~= nil and type(opts.lingering_time) ~= "number" then
        error("opts.lingering_time must be a number", 2)
    end

    if opts.lingering_time and
       opts.lingering_timeout and
       opts.lingering_timeout > opts.lingering_time
    then
        error("opts.lingering_time must be > opts.lingering_timeout", 2)
    end

    local self = {
        debug = opts.debug,

        on_frame = opts.on_frame,
        aggregate_fragments = opts.aggregate_fragments,

        lingering_time = opts.lingering_time,
        lingering_timeout = opts.lingering_timeout,
        connect_timeout = opts.connect_timeout,
        recv_timeout = opts.recv_timeout,
        send_timeout = opts.send_timeout,

        client = nil,
        client_max_fragments = opts.client_max_fragments,
        client_max_frame_size = opts.client_max_frame_size,

        upstream = nil,
        upstream_max_fragments = opts.upstream_max_fragments,
        upstream_max_frame_size = opts.upstream_max_frame_size,
        upstream_uri = nil,
    }

    return setmetatable(self, _mt)
end


function _M:dd(...)
    if self.debug then
        return log(DEBUG, ...)
    end
end


local function send_close(self, target, source, status, reason)
    local ctx = self[target]
    local ws = ctx and ctx.ws

    if not ws or not ws.sock then
        self:dd(target, " no connection established")
        return 1

    elseif ws.fatal or ctx.state == STATE.CLOSED then
        self:dd(target, " connection already closed/failed")
        return 1

    elseif ctx.state == STATE.CLOSING then
        self:dd(target, " close frame sent already")
        return 1
    end

    reason = reason or ""

    self:dd("sending close frame to ", target, ", initiator: ", source,
            ", status: ", status, ", reason: '", reason, "'")

    ctx.close_sent = now()
    ctx.state = STATE.CLOSING

    local sent, err = ws:send_close(status, reason)

    if sent then
        return sent

    elseif find(err, "closed", 1, true) then
        self:dd(target, " already closed")
        return 1
    end

    log(ERR, "failed sending close frame to ", target, ": ", err)

    return nil, err
end


local function close_client(self, source, status, reason)
    send_close(self, "client", source, status, reason)
end


local function close_upstream(self, source, status, reason)
    send_close(self, "upstream", source, status, reason)
end


local function close(self, source, client_status, client_reason, upstream_status, upstream_reason)
    close_client(self, source, client_status, client_reason)
    close_upstream(self, source, upstream_status, upstream_reason)
end


local function forwarder_close(self, role, code, data, peer_code, peer_data)
    local client_status, client_reason
    local upstream_status, upstream_reason

    if role == "client" then
        client_status = code
        client_reason = data
        upstream_status = peer_code
        upstream_reason = peer_data
    else
        -- target == "upstream"
        client_status = peer_code
        client_reason = peer_data
        upstream_status = code
        upstream_reason = data
    end

    return close(self, "proxy", client_status, client_reason,
                 upstream_status, upstream_reason)
end


local function forwarder(proxy, self, peer)
    local role = self.role
    local buf = self.frame_buf
    local on_frame = proxy.on_frame
    local max_frame_size = self.max_frame_size
    local max_fragments = self.max_fragments

    -- for the sake of consistency we accept timeout args in milliseconds, but
    -- lingering_time is measured against ngx.now(), so convert it back to
    -- seconds
    local lingering_time = (proxy.lingering_time or LINGERING_TIME) / 1000
    local lingering_timeout = proxy.lingering_timeout or LINGERING_TIMEOUT
    local recv_timeout = proxy.recv_timeout
    local send_timeout = proxy.send_timeout

    local frame_typ
    local frame_size, frame_count = 0, 0

    local co = co_running()

    local ws, peer_ws = self.ws, peer.ws

    while true do
        if peer.state == STATE.CLOSING then
            log(DEBUG, "peer (", peer, ") has been sent a close frame, ",
                       role, " forwarder exiting")

            return role

        elseif peer.state == STATE.CLOSED then
            log(DEBUG, "peer (", peer, ") connection is closed, ",
                       role, " forwarder exiting")

            self.state = STATE.CLOSED
            return role

        elseif self.state == STATE.CLOSING then
            proxy:dd(role, " lingering")

            self.close_sent = self.close_sent or now()

            if (now() - self.close_sent) > lingering_time then
                log(INFO, "lingering time expired waiting for ", role,
                          " to send more data, forwarder exiting")

                self.state = STATE.CLOSED
                return role, "linger expired"
            end

            recv_timeout = lingering_timeout or recv_timeout
        end

        proxy:dd(role, " receiving frame...")

        if recv_timeout then
            ws:set_timeout(recv_timeout)
        end

        local data, typ, err = ws:recv_frame()
        if not data then
            if find(err, "timeout", 1, true) then
                if self.state == STATE.CLOSING then
                    log(INFO, role, " recv() timed out while lingering, closing")
                    return role, "linger timeout"
                end

                log(DEBUG, "timeout receiving frame from ", role, ", reopening")

            elseif find(err, "closed", 1, true) then
                log(INFO, role, " recv() connection closed, exiting")
                self.state = STATE.CLOSED
                return role

            elseif find(err, "client aborted", 1, true) then
                log(INFO, role, " recv() aborted connection, exiting")
                self.state = STATE.CLOSED
                return role

            elseif find(err, "exceeding max payload len", 1, true) then
                log(INFO, role, " recv() frame size exceeds limit ",
                          "(", max_frame_size, "), closing")

                -- lua-resty-websocket sets this "fatal" flag if recv_frame()
                -- returns an error and then refuses all future calls to
                -- send_frame() if it is set.
                --
                -- While we still have data left over in our recv buffer, we're
                -- still perfectly capable of sending a close frame before
                -- terminating the connection
                ws.fatal = false

                forwarder_close(proxy, role, 1009, "Payload Too Large", 1001, "")

                ws.fatal = true

                self.state = STATE.CLOSED
                return role

            else
                log(ERR, role, " recv() failed: ", err)
                self.state = STATE.CLOSED
                return role, err
            end
        end

        -- a close frame was sent to our peer outside of the forwarder context
        if peer.state >= STATE.CLOSED then
            return role
        end

        -- special flags

        local code
        local opcode = OPCODE[typ]
        local fin = true
        if err == "again" then
            fin = false
            err = nil
        end

        if typ then
            if not opcode then
                log(ERR, "NYI - ", role, " sent unknown frame type: ", typ,
                         " (dropping connection)")

                self.state = STATE.CLOSED
                return role, "unknown frame type : " .. tostring(typ)
            end

            if typ == "close" then
                code = err
            end

            -- debug

            if proxy.debug and (not err or typ == "close") then
                local extra = ""
                local arrow

                if typ == "close" then
                    arrow = role == "client" and "--x" or "x--"

                else
                    arrow = role == "client" and "-->" or "<--"
                end

                local payload = data and gsub(data, "\n", "\\n") or ""
                if #payload > DEBUG_PAYLOAD_MAX_LEN then
                    payload = sub(payload, 1, DEBUG_PAYLOAD_MAX_LEN) .. "[...]"
                end

                if code then
                    extra = fmt("\n  code: %d", code)
                end

                if frame_typ then
                    extra = fmt("\n  initial type: \"%s\"", frame_typ)
                end

                proxy:dd(fmt("\n[frame] downstream %s resty.proxy %s upstream\n" ..
                            "  aggregating: %s\n" ..
                            "  type: \"%s\"%s\n" ..
                            "  payload: %s (len: %d)\n" ..
                            "  fin: %s",
                            arrow, arrow,
                            proxy.aggregate_fragments,
                            typ, extra,
                            fmt("%q", payload), data and #data or 0,
                            fin))
            end

            local bytes
            local forward = true
            local data_frame = typ == "text"
                               or typ == "binary"
                               or typ == "continuation"

            -- limits

            if data_frame then
                frame_size = frame_size + #data

                if max_frame_size and frame_size > max_frame_size then
                    log(INFO, role, " frame size (", frame_size, ") exceeds",
                              "  limit (", max_frame_size, "), closing")

                    forwarder_close(proxy, role, 1009, "Payload Too Large", 1001, "")

                    return role
                end

                frame_count = frame_count + 1

                if max_fragments and frame_count > max_fragments then
                    log(INFO, role, " frame count (", frame_count, ") ",
                              "exceeds limit (", max_fragments, "), closing")

                    forwarder_close(proxy, role, 1009, "Payload Too Large", 1001, "")

                    return role
                end
            end


            -- fragmentation

            if proxy.aggregate_fragments and data_frame then
                if not fin then
                    proxy:dd(role, " received fragmented frame, buffering")
                    insert(buf, data)
                    forward = false

                    -- stash data frame type of initial fragment
                    frame_typ = frame_typ or typ

                    -- continue

                elseif #buf > 0 then
                    proxy:dd(role, " received last fragmented frame, forwarding")
                    insert(buf, data)
                    data = concat(buf, "")
                    clear_tab(buf)

                    -- restore initial fragment type and opcode
                    typ = frame_typ
                    frame_typ = nil
                    opcode = OPCODE[typ]
                end
            end

            -- forward

            if forward then

                -- callback

                if on_frame then
                    local updated, updated_code = on_frame(proxy, role, typ,
                                                           data, fin, code)
                    if updated ~= nil then
                        if type(updated) ~= "string" then
                            error("opts.on_frame return value must be " ..
                                  "nil or a string")
                        end
                    end

                    data = updated

                    if typ == "close" and updated_code ~= nil then
                        if type(updated_code) ~= "number" then
                            error("opts.on_frame status code return value " ..
                                  "must be nil or a number")
                        end

                        code = updated_code
                    end

                    -- the on_frame callback my have yielded, so we need to
                    -- re-check our state
                    if peer.state >= STATE.CLOSED then
                        return role
                    end
                end

                if on_frame and data == nil then
                    proxy:dd(role, " dropping ", typ, " frame after on_frame handler requested it")

                    -- continue: while true

                else
                    if send_timeout then
                        peer_ws:set_timeout(send_timeout)
                    end

                    if typ == "close" then
                        send_close(proxy, peer.role, role, code, data)
                        return role
                    else
                        bytes, err = peer_ws:send_frame(fin, opcode, data)
                        if not bytes then
                            log(ERR, "failed forwarding frame from ", role,
                                     ": ", err)
                        end
                    end
                end


                if data_frame then
                    frame_size = 0
                    frame_count = 0
                end
            end

            -- continue: while true
        end

        proxy:dd(role, " yielding")

        yield(co)
    end
end


function _M:connect_upstream(uri, opts)
    if self.upstream then
        log(WARN, "connection with upstream (", self.upstream_uri, ")",
                  " already established")
        return true
    end

    self:dd("connecting to \"", uri, "\" upstream")

    local ws, err = ws_client:new()
    if not ws then
        return nil, err
    end

    if self.connect_timeout then
        ws:set_timeout(self.connect_timeout)
    end

    local ok, res
    ok, err, res = ws:connect(uri, opts)
    if not ok then
        return nil, err, res
    end

    self:dd("connected to \"", uri, "\" upstream")

    self.upstream = new_ctx(self, "upstream", ws)
    self.upstream_uri = uri

    return true, nil, res
end


function _M:connect_client()
    if self.client then
        log(WARN, "client handshake already completed")
        return true
    end

    self:dd("completing client handshake")

    local ws, err = ws_server:new()
    if not ws then
        return nil, err
    end

    self:dd("completed client handshake")

    self.client = new_ctx(self, "client", ws)

    return true
end


function _M:connect(uri, upstream_opts)
    local ok, err = self:connect_upstream(uri, upstream_opts)
    if not ok then
        return nil, "failed connecting to upstream: " .. err
    end

    ok, err = self:connect_client()
    if not ok then
        return nil, "failed client handshake: " .. err
    end

    return true
end


function _M:execute()
    if not self.client then
        return nil, "client handshake not complete"
    end

    if not self.upstream then
        return nil, "upstream connection not established"
    end

    local client = spawn(forwarder, self, self.client, self.upstream)
    local upstream = spawn(forwarder, self, self.upstream, self.client)

    local ok, res, err = wait(client, upstream)
    if not ok then
        log(ERR, "failed to wait for websocket proxy threads: ", res or err)

    elseif res == "client" then

        self:dd("client thread terminated")

        if self.client.state <= STATE.CLOSING then
            self:dd("waiting for upstream thread to terminate")
            wait(upstream)

        elseif self.client.state == STATE.CLOSED then
            send_close(self, "upstream", "proxy", 1001)
        end

        kill(upstream)

        self:dd("closing \"", self.upstream_uri, "\" upstream websocket")

        self.upstream.ws:close()

    elseif res == "upstream" then

        self:dd("upstream thread terminated")

        if self.upstream.state <= STATE.CLOSING then
            self:dd("waiting for client thread to terminate")
            wait(client)

        elseif self.upstream.state == STATE.CLOSED then
            send_close(self, "client", "proxy", 1001)
        end

        kill(client)
    end

    self.client = nil
    self.upstream = nil
    self.upstream_uri = nil

    if err then
        return nil, err
    end

    return true
end


function _M:close(client_status, client_reason, upstream_status, upstream_reason)
    return close(self, "proxy", client_status, client_reason,
                 upstream_status, upstream_reason)
end

function _M:close_upstream(status, reason)
    return close_upstream(self, "proxy", status, reason)
end

return _M
