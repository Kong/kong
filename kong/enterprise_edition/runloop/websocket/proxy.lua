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
local fmt = string.format
local sub = string.sub
local gsub = string.gsub
local find = string.find
local log = ngx.log
local now = ngx.now
local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local kill = ngx.thread.kill


local _DEBUG_PAYLOAD_MAX_LEN = 24
local _STATES = {
    INIT = 1,
    ESTABLISHED = 2,
    CLOSING = 3,
    CLOSED = 4,
}

local _TYP2OPCODE = {
    ["continuation"] = 0x0,
    ["text"] = 0x1,
    ["binary"] = 0x2,
    ["close"] = 0x8,
    ["ping"] = 0x9,
    ["pong"] = 0xa,
}

local LINGERING_TIME = 30000
local LINGERING_TIMEOUT = 5000


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


    -- TODO: provide a means of passing options through to the
    -- resty.websocket.client constructor (like `max_payload_len`)
    local client, err = ws_client:new()
    if not client then
        return nil, "failed to create client: " .. err
    end

    local self = {
        client = client,
        server = nil,
        upstream_uri = nil,
        on_frame = opts.on_frame,
        recv_timeout = opts.recv_timeout,
        connect_timeout = opts.connect_timeout,
        client_max_frame_size = opts.client_max_frame_size,
        client_max_fragments = opts.client_max_fragments,
        upstream_max_frame_size = opts.upstream_max_frame_size,
        upstream_max_fragments = opts.upstream_max_fragments,
        lingering_timeout = opts.lingering_timeout,
        lingering_time = opts.lingering_time,
        aggregate_fragments = opts.aggregate_fragments,
        debug = opts.debug,
        client_state = _STATES.INIT,
        upstream_state = _STATES.INIT,
        co_client = nil,
        co_server = nil,
    }

    return setmetatable(self, _mt)
end


function _M:dd(...)
    if self.debug then
        return log(ngx.DEBUG, ...)
    end
end


local function send_close(self, target, source, status, reason)
    reason = reason or ""

    self:dd("closing ", target, "\ninitiator: ", source, "\nstatus: ", status,
            "\nreason: '", reason, "'\n")

    self.close_sent = self.close_sent or now()

    local ws
    if target == "client" then
        ws = self.server
    else
        -- target == "upstream"
        ws = self.client
    end

    if ws.fatal then
        self:dd(target, " already closed")
        return 1
    end

    local sent, err = ws:send_close(status, reason)

    if sent then
        return sent

    elseif find(err, "closed", 1, true) then
        self:dd(target, " already closed")
        return 1
    end

    log(ngx.ERR, "failed sending close frame to ", target, ": ", err)

    return nil, err
end


local function close(self, source, client_status, client_reason, upstream_status, upstream_reason)
    send_close(self, "client", source, client_status, client_reason)
    send_close(self, "upstream", source, upstream_status, upstream_reason)
    self.client_state = _STATES.CLOSING
    self.upstream_state = _STATES.CLOSING
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

    return close(self, role, client_status, client_reason,
                 upstream_status, upstream_reason)
end


local function forwarder(self, ctx)
    local role = ctx.role
    local buf = ctx.buf
    local self_ws, peer_ws
    local self_state, peer_state
    local peer
    local frame_typ
    local frame_size, frame_count = 0, 0
    local on_frame = self.on_frame
    local max_frame_size = ctx.max_frame_size
    local max_fragments = ctx.max_fragments

    -- for the sake of consistency we accept timeout args in milliseconds, but
    -- lingering_time is measured against ngx.now(), so convert it back to
    -- seconds
    local lingering_time = (self.lingering_time or LINGERING_TIME) / 1000
    local lingering_timeout = self.lingering_timeout or LINGERING_TIMEOUT

    local recv_timeout = self.recv_timeout

    self_state = role .. "_state"

    --assert(self[self_state] == _STATES.ESTABLISHED)

    if role == "client" then
        self_ws = self.server
        peer_ws = self.client
        peer_state = "upstream_state"
        peer = "upstream"

    else
        -- role == "upstream"
        self_ws = self.client
        peer_ws = self.server
        peer_state = "client_state"
        peer = "client"
    end

    while true do
        if self[self_state] >= _STATES.CLOSING then
            return role

        elseif self[peer_state] == _STATES.CLOSED then
            log(ngx.INFO, role, " exiting due to peer closure")
            self[self_state] = _STATES.CLOSED
            return role

        elseif self[peer_state] == _STATES.CLOSING then
            if (now() - self.close_sent) > lingering_time then
                log(ngx.INFO, "closing due to linger time")
                self[self_state] = _STATES.CLOSED
                return role, "linger expired"
            end

            recv_timeout = lingering_timeout
        end

        if recv_timeout then
            self_ws:set_timeout(recv_timeout)
        end

        self:dd(role, " receiving frame...")

        local data, typ, err = self_ws:recv_frame()
        if not data then
            if find(err, "timeout", 1, true) then
                if self[peer_state] == _STATES.CLOSING then
                    log(ngx.INFO, role, "timed out while lingering, closing")
                    return role, "linger timeout"
                end

                log(ngx.INFO, fmt("timeout receiving frame from %s, reopening",
                                  role))
                -- continue

            elseif find(err, "closed", 1, true) then
                self[self_state] = _STATES.CLOSED
                return role

            elseif find(err, "client aborted", 1, true) then
                log(ngx.WARN, role, " aborted connection, exiting")
                self[self_state] = _STATES.CLOSED
                return role

            else
                log(ngx.ERR, fmt("failed receiving frame from %s: %s",
                                 role, err))
                self[self_state] = _STATES.CLOSED
                return role, err
            end
        end

        -- a close frame was sent to our peer outside of the forwarder context
        if self[self_state] >= _STATES.CLOSING or
           self[peer_state] == _STATES.CLOSED
        then
            return role
        end

        -- special flags

        local code
        local opcode = _TYP2OPCODE[typ]
        local fin = true
        if err == "again" then
            fin = false
            err = nil
        end

        if typ then
            if not opcode then
                log(ngx.EMERG, "NYI - unknown frame type: ", typ,
                               " (dropping connection)")
                return
            end

            if typ == "close" then
                code = err
            end

            -- debug

            if self.debug and (not err or typ == "close") then
                local extra = ""
                local arrow

                if typ == "close" then
                    arrow = role == "client" and "--x" or "x--"

                else
                    arrow = role == "client" and "-->" or "<--"
                end

                local payload = data and gsub(data, "\n", "\\n") or ""
                if #payload > _DEBUG_PAYLOAD_MAX_LEN then
                    payload = sub(payload, 1, _DEBUG_PAYLOAD_MAX_LEN) .. "[...]"
                end

                if code then
                    extra = fmt("\n  code: %d", code)
                end

                if frame_typ then
                    extra = fmt("\n  initial type: \"%s\"", frame_typ)
                end

                self:dd(fmt("\n[frame] downstream %s resty.proxy %s upstream\n" ..
                            "  aggregating: %s\n" ..
                            "  type: \"%s\"%s\n" ..
                            "  payload: %s (len: %d)\n" ..
                            "  fin: %s",
                            arrow, arrow,
                            self.aggregate_fragments,
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
                    log(ngx.INFO, fmt("%s frame size (%s) exceeds limit, closing",
                                      role, frame_size))
                    forwarder_close(self, role, 1009, "Payload Too Large", 1001, "")

                    return role
                end

                frame_count = frame_count + 1

                if max_fragments and frame_count > max_fragments then
                    log(ngx.INFO, fmt("%s frame count (%s) exceeds limit, closing",
                                      role, frame_count))
                    forwarder_close(self, role, 1009, "Payload Too Large", 1001, "")

                    return role
                end
            end


            -- fragmentation

            if self.aggregate_fragments and data_frame then
                if not fin then
                    self:dd(role, " received fragmented frame, buffering")
                    insert(buf, data)
                    forward = false

                    -- stash data frame type of initial fragment
                    frame_typ = frame_typ or typ

                    -- continue

                elseif #buf > 0 then
                    self:dd(role, " received last fragmented frame, forwarding")
                    insert(buf, data)
                    data = concat(buf, "")
                    clear_tab(buf)

                    -- restore initial fragment type and opcode
                    typ = frame_typ
                    frame_typ = nil
                    opcode = _TYP2OPCODE[typ]
                end
            end

            -- forward

            if forward then

                -- callback

                if on_frame then
                    local updated, updated_code = on_frame(self, role, typ,
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
                    if self[self_state] >= _STATES.CLOSING or
                       self[peer_state] == _STATES.CLOSED
                    then
                        return role
                    end
                end

                if on_frame and data == nil then
                    self:dd(role, " dropping ", typ, " frame after on_frame handler requested it")

                    -- continue: while true

                else
                    if typ == "close" then
                        log(ngx.INFO, "forwarding close with code: ", code, ", payload: ",
                                      data)

                        send_close(self, peer, role, code, data)
                        self[self_state] = _STATES.CLOSING
                        return role
                    else
                        bytes, err = peer_ws:send_frame(fin, opcode, data)
                    end

                    if not bytes then
                        log(ngx.ERR, fmt("failed forwarding a frame from %s: %s",
                                         role, err))
                        -- continue
                    end
                end


                if data_frame then
                    frame_size = 0
                    frame_count = 0
                end
            end

            -- continue: while true
        end

        self:dd(role, " yielding")

        yield(self)
    end
end


function _M:connect_upstream(uri, opts)
    if self.upstream_state == _STATES.ESTABLISHED then
        log(ngx.WARN, fmt("connection with upstream at %q already established",
                          self.upstream_uri))
        return true
    end

    self:dd("connecting to \"", uri, "\" upstream")

    if self.connect_timeout then
      self.client:set_timeout(self.connect_timeout)
    end

    local ok, err, res = self.client:connect(uri, opts)
    if not ok then
        return nil, err, res
    end

    self:dd("connected to \"", uri, "\" upstream")

    self.upstream_uri = uri
    self.upstream_state = _STATES.ESTABLISHED

    return true, nil, res
end


function _M:connect_client()
    if self.client_state == _STATES.ESTABLISHED then
        log(ngx.WARN, "client handshake already completed")
        return true
    end

    self:dd("completing client handshake")

    local server, err = ws_server:new()
    if not server then
        return nil, err
    end

    self:dd("completed client handshake")

    self.server = server
    self.client_state = _STATES.ESTABLISHED

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
    if self.client_state ~= _STATES.ESTABLISHED then
        return nil, "client handshake not complete"
    end

    if self.upstream_state ~= _STATES.ESTABLISHED then
        return nil, "upstream connection not established"
    end

    self.co_client = spawn(forwarder, self, {
        role = "client",
        buf = new_tab(0, 0),
        max_frame_size = self.client_max_frame_size,
        max_fragments = self.client_max_fragments,
    })

    self.co_server = spawn(forwarder, self, {
        role = "upstream",
        buf = new_tab(0, 0),
        max_frame_size = self.upstream_max_frame_size,
        max_fragments = self.upstream_max_fragments,
    })

    local ok, res, err = wait(self.co_client, self.co_server)
    if not ok then
        log(ngx.ERR, "failed to wait for websocket proxy threads: ", err)

    elseif res == "client" then
        --assert(self.client_state == _STATES.CLOSING
        --       or self.client_state == _STATES.CLOSED)

        self:dd(res, " thread terminated, killing server thread")

        if self.client_state == _STATES.CLOSING then
            wait(self.co_server)

        elseif self.client_state == _STATES.CLOSED then
            send_close(self, "upstream", "proxy", 1001)
        end

        kill(self.co_server)

        self:dd("closing \"", self.upstream_uri, "\" upstream websocket")

        self.client:close()

    elseif res == "upstream" then
        --assert(self.upstream_state == _STATES.CLOSING
        --       or self.upstream_state == _STATES.CLOSED)

        self:dd(res, " thread terminated, killing client thread")

        if self.upstream_state == _STATES.CLOSING then
            wait(self.co_client)

        elseif self.upstream_state == _STATES.CLOSED then
            send_close(self, "client", "proxy", 1001)
        end

        kill(self.co_client)
    end

    self.co_client = nil
    self.co_server = nil
    self.client_state = _STATES.INIT
    self.upstream_state = _STATES.INIT
    self.close_sent = nil

    if err then
        return nil, err
    end

    return true
end


function _M:close(client_status, client_reason, upstream_status, upstream_reason)
    return close(self, "proxy", client_status, client_reason,
                 upstream_status, upstream_reason)
end


return _M
