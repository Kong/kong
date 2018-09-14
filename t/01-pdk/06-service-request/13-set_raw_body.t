use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

$ENV{TEST_NGINX_NXSOCK} ||= html_dir();

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: service.request.set_raw_body() errors if not a string
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_raw_body, 127001)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
body must be a string
--- no_error_log
[error]



=== TEST 2: service.request.set_raw_body() errors if given no arguments
--- http_config eval: $t::Util::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local pok, err = pcall(pdk.service.request.set_raw_body)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
body must be a string
--- no_error_log
[error]



=== TEST 3: service.request.set_raw_body() accepts an empty string
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
            }
        }
    }
}
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_raw_body("")

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
body: {nil}
--- no_error_log
[error]



=== TEST 4: service.request.set_raw_body() sets the body
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
            }
        }
    }
}
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_raw_body("foo=bar&bla&baz=hello%20world")

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
body: {foo=bar&bla&baz=hello%20world}
--- no_error_log
[error]



=== TEST 5: service.request.set_raw_body() sets a short body
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
            }
        }
    }
}
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_raw_body("ovo")

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
body: {ovo}
--- no_error_log
[error]



=== TEST 6: service.request.set_raw_body() is 8-bit clean
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local body = tostring(ngx.req.get_body_data())
                local out = {}
                local n = 1
                for i = 1, #body do
                    out[n] = string.byte(body, i, i)
                    n = n + 1
                    if n == 21 then
                        ngx.say(table.concat(out, " "))
                        n = 1
                    end
                end
                ngx.say(table.concat(out, " ", 1, 16))
            }
        }
    }
}
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local x = {}
            for i = 0, 255 do
                x[i + 1] = string.char(i)
            end
            pdk.service.request.set_raw_body(table.concat(x))

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19
20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39
40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59
60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79
80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99
100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119
120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139
140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159
160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179
180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199
200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219
220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239
240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255
--- no_error_log
[error]



=== TEST 7: service.request.set_raw_body() replaces any existing body
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.say("body: {", tostring(ngx.req.get_body_data()), "}")
            }
        }
    }
}
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_raw_body("I am another body")

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
POST /t

I am a body
--- response_body
body: {I am another body}
--- no_error_log
[error]



=== TEST 8: service.request.set_raw_body() has no size limits for sending
--- http_config eval
qq{
    $t::Util::HttpConfig

    server {
        listen unix:$ENV{TEST_NGINX_NXSOCK}/nginx.sock;

        client_max_body_size 10m;
        client_body_buffer_size 10m;

        location /t {
            content_by_lua_block {
                ngx.req.read_body()
                local body = tostring(ngx.req.get_body_data())
                local content_length = tostring(ngx.req.get_headers()["Content-Length"])
                ngx.say("body size: {" .. tostring(#body) .. "}")
                ngx.say("content length header: {" .. content_length .. "}")
            }
        }
    }
}
--- config
    location = /t {

        set $upstream_host '';

        access_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.service.request.set_raw_body(("x"):rep(10000000))

        }

        proxy_set_header Host $upstream_host;
        proxy_pass http://unix:/$TEST_NGINX_NXSOCK/nginx.sock;
    }
--- request
GET /t
--- response_body
body size: {10000000}
content length header: {10000000}
--- no_error_log
[error]
