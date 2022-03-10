local frame = require "kong.events.frame"

local _recv_frame = frame.recv
local _send_frame = frame.send

local ngx = ngx
local tcp = ngx.socket.tcp
local re_match = ngx.re.match
local req_sock = ngx.req.socket
local ngx_header = ngx.header
local str_sub  = string.sub
local setmetatable = setmetatable


local function recv_frame(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized yet"
    end

    return _recv_frame(sock)
end


local function send_frame(self, payload)
    local sock = self.sock
    if not sock then
        return nil, "not initialized yet"
    end

    return _send_frame(sock, payload)
end


local _Server = {
    _VERSION = "0.0.1",
    recv_frame = recv_frame,
    send_frame = send_frame,
}

local _server_mt = { __index = _Server }


function _Server.new(self, opts)
    if ngx.headers_sent then
        return nil, "response header already sent"
    end

    ngx_header["Upgrade"] = "Kong-Worker-Events/1"
    ngx_header["Content-Type"] = nil
    ngx.status = 101

    local ok, err = ngx.send_headers()
    if not ok then
        return nil, "failed to send response header: " .. (err or "unknonw")
    end

    ok, err = ngx.flush(true)
    if not ok then
        return nil, "failed to flush response header: " .. (err or "unknown")
    end

    local sock
    sock, err = req_sock(true)
    if not sock then
        return nil, err
    end

    return setmetatable({
        sock = sock,
    }, _server_mt)
end


local _Client = {
    _VERSION = "0.0.1",
    recv_frame = recv_frame,
    send_frame = send_frame,
}

local _client_mt = { __index = _Client }


function _Client.new(self, opts)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end

    return setmetatable({
        sock = sock,
    }, _client_mt)
end


function _Client.connect(self, unix)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    if type(unix) ~= "string" then
        return nil, "unix must be a string"
    end

    if str_sub(unix, 1, 5) ~= "unix:" then
        unix = "unix:" .. unix
    end

    local ok, err = sock:connect(unix)
    if not ok then
        return nil, "failed to connect: " .. err
    end

    local req = "GET / HTTP/1.1\r\nHost: localhost" ..
                "\r\nConnection: Upgrade\r\nUpgrade: Kong-Worker-Events/1\r\n\r\n"

    local bytes, err = sock:send(req)
    if not bytes then
        return nil, "failed to send the handshake request: " .. err
    end

    local header_reader = sock:receiveuntil("\r\n\r\n")
    local header, err, _ = header_reader()
    if not header then
        return nil, "failed to receive response header: " .. err
    end

    local m, _ = re_match(header, [[^\s*HTTP/1\.1\s+]], "jo")
    if not m then
        return nil, "bad HTTP response status line: " .. header
    end

    return true
end


return {
    server = _Server,
    client = _Client,
}
