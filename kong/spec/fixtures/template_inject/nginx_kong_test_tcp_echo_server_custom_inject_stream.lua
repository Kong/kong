return [[
server {
    listen 8188;
    listen 8189 ssl;

> for i = 1, #ssl_cert do
    ssl_certificate     $(ssl_cert[i]);
    ssl_certificate_key $(ssl_cert_key[i]);
> end
    ssl_protocols TLSv1.2 TLSv1.3;

    content_by_lua_block {
        local sock = assert(ngx.req.socket())
        local data = sock:receive()  -- read a line from downstream
        if data then
            sock:send(data.."\n") -- echo whatever was sent
            ngx.log(ngx.INFO, "received data: " .. data)
        else
            ngx.log(ngx.WARN, "Nothing received")
        end
    }
}
]]
