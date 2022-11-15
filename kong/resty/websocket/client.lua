-- Copyright (C) Yichun Zhang (agentzh)


-- FIXME: this library is very rough and is currently just for testing
--        the websocket server.


local wbproto = require "resty.websocket.protocol"
local bit = require "bit"


local _recv_frame = wbproto.recv_frame
local _send_frame = wbproto.send_frame
local new_tab = wbproto.new_tab
local tcp = ngx.socket.tcp
local re_match = ngx.re.match
local encode_base64 = ngx.encode_base64
local concat = table.concat
local char = string.char
local str_find = string.find
local rand = math.random
local rshift = bit.rshift
local band = bit.band
local setmetatable = setmetatable
local type = type
local debug = ngx.config.debug
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ssl_support = true

if not ngx.config
    or not ngx.config.ngx_lua_version
    or ngx.config.ngx_lua_version < 9011
then
    ssl_support = false
end

local _M = new_tab(0, 13)
_M._VERSION = '0.09'


local mt = { __index = _M }


function _M.new(self, opts)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end

    local max_payload_len, send_unmasked, timeout
    if opts then
        max_payload_len = opts.max_payload_len
        send_unmasked = opts.send_unmasked
        timeout = opts.timeout

        if timeout then
            sock:settimeout(timeout)
        end
    end

    return setmetatable({
        sock = sock,
        max_payload_len = max_payload_len or 65535,
        send_unmasked = send_unmasked,
    }, mt)
end


function _M.connect(self, uri, opts)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local m, err = re_match(uri, [[^(wss?)://([^:/]+)(?::(\d+))?(.*)]], "jo")
    if not m then
        if err then
            return nil, "failed to match the uri: " .. err
        end

        return nil, "bad websocket uri"
    end

    local scheme = m[1]
    local host = m[2]
    local port = m[3]
    local path = m[4]

    -- ngx.say("host: ", host)
    -- ngx.say("port: ", port)

    if not port then
        port = 80
    end

    if path == "" then
        path = "/"
    end

    local ssl_verify, server_name, headers, proto_header, origin_header, sock_opts = false
    local client_cert, client_priv_key

    if opts then
        local protos = opts.protocols
        if protos then
            if type(protos) == "table" then
                proto_header = "\r\nSec-WebSocket-Protocol: "
                               .. concat(protos, ",")

            else
                proto_header = "\r\nSec-WebSocket-Protocol: " .. protos
            end
        end

        local origin = opts.origin
        if origin then
            origin_header = "\r\nOrigin: " .. origin
        end

        local pool = opts.pool
        if pool then
            sock_opts = { pool = pool }
        end

        client_cert = opts.client_cert
        client_priv_key = opts.client_priv_key

        if client_cert then
            assert(client_priv_key,
                   "client_priv_key must be provided with client_cert")
        end

        if opts.ssl_verify or opts.server_name then
            if not ssl_support then
                return nil, "ngx_lua 0.9.11+ required for SSL sockets"
            end
            ssl_verify = opts.ssl_verify
            server_name = opts.server_name or host
        end

        if opts.headers then
            headers = opts.headers
            if type(headers) ~= "table" then
                return nil, "custom headers must be a table"
            end
        end
    end

    local ok, err
    if sock_opts then
        ok, err = sock:connect(host, port, sock_opts)
    else
        ok, err = sock:connect(host, port)
    end
    if not ok then
        return nil, "failed to connect: " .. err
    end

    if scheme == "wss" then
        if not ssl_support then
            return nil, "ngx_lua 0.9.11+ required for SSL sockets"
        end

        if client_cert then
            ok, err = sock:setclientcert(client_cert, client_priv_key)
            if not ok then
                return nil, "ssl client cert failed: " .. err
            end
        end

        ok, err = sock:sslhandshake(false, server_name, ssl_verify)
        if not ok then
            return nil, "ssl handshake failed: " .. err
        end
    end

    -- check for connections from pool:

    local count, err = sock:getreusedtimes()
    if not count then
        return nil, "failed to get reused times: " .. err
    end
    if count > 0 then
        -- being a reused connection (must have done handshake)
        return 1
    end

    local custom_headers
    if headers then
        custom_headers = concat(headers, "\r\n")
        custom_headers = "\r\n" .. custom_headers
    end

    -- do the websocket handshake:

    local bytes = char(rand(256) - 1, rand(256) - 1, rand(256) - 1,
                       rand(256) - 1, rand(256) - 1, rand(256) - 1,
                       rand(256) - 1, rand(256) - 1, rand(256) - 1,
                       rand(256) - 1, rand(256) - 1, rand(256) - 1,
                       rand(256) - 1, rand(256) - 1, rand(256) - 1,
                       rand(256) - 1)

    local key = encode_base64(bytes)
    local req = "GET " .. path .. " HTTP/1.1\r\nUpgrade: websocket\r\nHost: "
                .. host .. ":" .. port
                .. "\r\nSec-WebSocket-Key: " .. key
                .. (proto_header or "")
                .. "\r\nSec-WebSocket-Version: 13"
                .. (origin_header or "")
                .. "\r\nConnection: Upgrade"
                .. (custom_headers or "")
                .. "\r\n\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, "failed to send the handshake request: " .. err
    end

    local header_reader = sock:receiveuntil("\r\n\r\n")
    -- FIXME: check for too big response headers
    local header, err, partial = header_reader()
    if not header then
        return nil, "failed to receive response header: " .. err
    end

    -- error("header: " .. header)

    -- FIXME: verify the response headers

    m, err = re_match(header, [[^\s*HTTP/1\.1\s+]], "jo")
    if not m then
        return nil, "bad HTTP response status line: " .. header
    end

    return 1
end


function _M.set_timeout(self, time)
    local sock = self.sock
    if not sock then
        return nil, nil, "not initialized yet"
    end

    return sock:settimeout(time)
end


function _M.recv_frame(self)
    if self.fatal then
        return nil, nil, "fatal error already happened"
    end

    local sock = self.sock
    if not sock then
        return nil, nil, "not initialized yet"
    end

    local data, typ, err =  _recv_frame(sock, self.max_payload_len, false)
    if not data and not str_find(err, ": timeout", 1, true) then
        self.fatal = true
    end
    return data, typ, err
end


local function send_frame(self, fin, opcode, payload)
    if self.fatal then
        return nil, "fatal error already happened"
    end

    if self.closed then
        return nil, "already closed"
    end

    local sock = self.sock
    if not sock then
        return nil, "not initialized yet"
    end

    local bytes, err = _send_frame(sock, fin, opcode, payload,
                                   self.max_payload_len,
                                   not self.send_unmasked)
    if not bytes then
        self.fatal = true
    end
    return bytes, err
end
_M.send_frame = send_frame


function _M.send_text(self, data)
    return send_frame(self, true, 0x1, data)
end


function _M.send_binary(self, data)
    return send_frame(self, true, 0x2, data)
end


local function send_close(self, code, msg)
    local payload
    if code then
        if type(code) ~= "number" or code > 0x7fff then
            return nil, "bad status code"
        end
        payload = char(band(rshift(code, 8), 0xff), band(code, 0xff))
                        .. (msg or "")
    end

    if debug then
        ngx_log(ngx_DEBUG, "sending the close frame")
    end

    local bytes, err = send_frame(self, true, 0x8, payload)

    if not bytes then
        self.fatal = true
    end

    self.closed = true

    return bytes, err
end
_M.send_close = send_close


function _M.send_ping(self, data)
    return send_frame(self, true, 0x9, data)
end


function _M.send_pong(self, data)
    return send_frame(self, true, 0xa, data)
end


function _M.close(self)
    if self.fatal then
        return nil, "fatal error already happened"
    end

    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    if not self.closed then
        local bytes, err = send_close(self)
        if not bytes then
            return nil, "failed to send close frame: " .. err
        end
    end

    return sock:close()
end


function _M.set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end


return _M
