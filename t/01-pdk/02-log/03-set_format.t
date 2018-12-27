use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;
use t::Util;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: kong.log.set_format() changes kong.log format and keeps prefix
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.set_format("log from kong.log: %message")

            pdk.log("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/\[kong\] log from kong\.log: hello world/
--- no_error_log
[error]



=== TEST 2: kong.log.set_format() changes kong.log format for all logging levels
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.set_format("log from kong.log: %message")

            pdk.log.notice("hello world")
            pdk.log.err("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log eval
[
qr/\[notice\] .*? log from kong\.log: hello world/,
qr/\[error\] .*? log from kong\.log: hello world/
]



=== TEST 3: log.set_format() makes log() still supports variadic arguments
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.set_format("log from kong.log: %message")

            pdk.log.notice("hello ", "world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
log from kong.log: hello world
--- no_error_log
[error]



=== TEST 4: log.set_format() accepts no modifier
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.set_format("a useless format")

            pdk.log.notice("hello ", "world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
a useless format
--- no_error_log
hello world



=== TEST 5: log.set_format() accepts multiple %message modifiers
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.set_format("%message | %message")

            pdk.log.notice("hello ", "world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
hello world | hello world
--- no_error_log
[error]



=== TEST 6: log.set_format() accepts %file_src modifier (by_lua chunk)
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.set_format("file_src(%file_src) %message")

            pdk.log.notice("hello ", "world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/file_src\(content_by_lua\(nginx\.conf:\d+\)\) hello world/
--- no_error_log
[error]



=== TEST 7: log.set_format() accepts %file_src modifier (Lua file)
--- user_files
>>> my_file.lua
local PDK = require "kong.pdk"
local pdk = PDK.new()

pdk.log.set_format("file_src(%file_src) %message")

pdk.log.notice("hello ", "world")
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_file html/my_file.lua;
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/file_src\(my_file\.lua\) hello world/
--- no_error_log
[error]



=== TEST 8: log.set_format() accepts %line_src modifier
--- user_files
>>> my_file.lua
local PDK = require "kong.pdk"
local pdk = PDK.new()

pdk.log.set_format("line_src(%line_src) %message")

local function my_func()
    pdk.log.notice("hello ", "world")
end

my_func()
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_file html/my_file.lua;
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/line_src\(7\) hello world/
--- no_error_log
[error]



=== TEST 9: log.set_format() accepts %func_name modifier
--- user_files
>>> my_file.lua
local PDK = require "kong.pdk"
local pdk = PDK.new()

pdk.log.set_format("func_name(%func_name) %message")

local function my_func()
    pdk.log.notice("hello ", "world")
end

my_func()
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_file html/my_file.lua;
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/func_name\(my_func\) hello world/
--- no_error_log
[error]



=== TEST 10: log.set_format() %func_name modifier prints '?' when none
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            pdk.log.set_format("func_name(%func_name) %message")

            pdk.log.notice("hello ", "world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/func_name\(\?\) hello world/
--- no_error_log
[error]



=== TEST 11: log.set_format() sets format of namespaced facility
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local log = pdk.log.new("my_namespace")

            log.set_format("log from facility: %message")

            log("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
log from facility: hello world
--- no_error_log
[error]



=== TEST 12: log.set_format() accepts %namespace modifier
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local log = pdk.log.new("my_namespace")

            log.set_format("{%namespace} %message")

            log("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
{my_namespace} hello world
--- no_error_log
[error]



=== TEST 13: log.set_format() does not consider escaped modifiers
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local log = pdk.log.new("my_namespace")

            log.set_format("%%namespace %%file_src %%func_name %%message %message")

            log("hello world")
        }
    }
--- request
GET /t
--- no_response_body
--- error_log
%%namespace %%file_src %%func_name %%message hello world
--- no_error_log
[error]



=== TEST 14: log.set_format() complex format
--- http_config eval: $t::Util::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local PDK = require "kong.pdk"
            local pdk = PDK.new()

            local log = pdk.log.new("my_namespace")

            log.set_format("[%%namespace: %namespace | %namespace, " ..
                           "%%file_src: %file_src | %file_src, " ..
                           "%%line_src: %line_src | %line_src, " ..
                           "%%func_name %func_name | %func_name, " ..
                           "%%message %message | %message]")

            local function my_func()
                log("hello world")
            end

            my_func()
        }
    }
--- request
GET /t
--- no_response_body
--- error_log eval
qr/\[kong\] \[%%namespace: my_namespace \| my_namespace, %%file_src: content_by_lua\(nginx.conf:\d+\) \| content_by_lua\(nginx.conf:\d+\), %%line_src: 14 \| 14, %%func_name my_func \| my_func, %%message hello world \| hello world\]/
--- no_error_log
[error]
