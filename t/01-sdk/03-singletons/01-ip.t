use strict;
use warnings FATAL => 'all';
use Test::Nginx::Socket::Lua;

plan tests => repeat_each() * (blocks() * 3);

run_tests();

__DATA__

=== TEST 1: ip singleton can be initialized
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            assert(sdk.init(nil, "ip"))

            ngx.say("sdk.ip: ", type(sdk.ip))
        }
    }
--- request
GET /t
--- response_body
sdk.ip: table
--- no_error_log
[error]



=== TEST 2: ip singleton errors if already initialized
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            assert(sdk.init(nil, "ip"))
            local ok, err = pcall(sdk.init, nil, "ip")
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
singleton already initialized or conflicting: ip
--- no_error_log
[error]



=== TEST 3: ip singleton errors if not initialized
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local ok, err = pcall(function()
                sdk.ip.is_trusted()
            end)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body_like
ip singleton not initialized
--- no_error_log
[error]



=== TEST 4: ip.is_trusted() trusts all IPs if trusted_ips = 0.0.0.0/0 (ipv4)
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local kong_conf = {
                trusted_ips = { "127.0.0.1", "0.0.0.0/0" }
            }

            assert(sdk.init(kong_conf, "ip"))

            local tests = {
                ["10.0.0.1"] = true,
                ["172.16.0.1"] = true,
                ["192.168.0.1"] = true,
                ["127.0.0.1"] = true,
            }

            local err

            for ip, res in pairs(tests) do
                local ok = sdk.ip.is_trusted(ip)
                if ok ~= res then
                    ngx.say(ip, " should be ", res, " but got: ", ok)
                    err = true
                end
            end

            if not err then
                ngx.say("ok")
            end
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 5: ip.is_trusted() trusts all IPs if trusted_ips = ::/0 (ipv6)
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local kong_conf = {
                trusted_ips = { "::1", "::/0" }
            }

            assert(sdk.init(kong_conf, "ip"))

            local tests = {
                ["2001:db8:85a3:8d3:1319:8a2e:370:7348"] = true,
                ["2001:db8:85a3::8a2e:370:7334"] = true,
                ["::1"] = true,
            }

            local err

            for ip, res in pairs(tests) do
                local ok = sdk.ip.is_trusted(ip)
                if ok ~= res then
                    ngx.say(ip, " should be ", res, " but got: ", ok)
                    err = true
                end
            end

            if not err then
                ngx.say("ok")
            end
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 6: ip.is_trusted() trusts none if no trusted_ip (ipv4)
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local kong_conf = {
                trusted_ips = {}
            }

            assert(sdk.init(kong_conf, "ip"))

            local tests = {
                ["10.0.0.1"] = false,
                ["172.16.0.1"] = false,
                ["192.168.0.1"] = false,
                ["127.0.0.1"] = false,
            }

            local err

            for ip, res in pairs(tests) do
                local ok = sdk.ip.is_trusted(ip)
                if ok ~= res then
                    ngx.say(ip, " should be ", res, " but got: ", ok)
                    err = true
                end
            end

            if not err then
                ngx.say("ok")
            end
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 7: ip.is_trusted() trusts none if no trusted_ip (ipv6)
--- config
    location = /t {
        content_by_lua_block {
            local SDK = require "kong.sdk"
            local sdk = SDK.new()

            local kong_conf = {
                trusted_ips = {}
            }

            assert(sdk.init(kong_conf, "ip"))

            local tests = {
                ["2001:db8:85a3:8d3:1319:8a2e:370:7348"] = false,
                ["2001:db8:85a3::8a2e:370:7334"] = false,
                ["::1"] = false,
            }

            local err

            for ip, res in pairs(tests) do
                local ok = sdk.ip.is_trusted(ip)
                if ok ~= res then
                    ngx.say(ip, " should be ", res, " but got: ", ok)
                    err = true
                end
            end

            if not err then
                ngx.say("ok")
            end
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]



=== TEST 8: ip.is_trusted() trusts range (ipv4)
--- SKIP: TODO
--- config
    location = /t {
        content_by_lua_block {

        }
    }
--- request
GET /t
--- response_body

--- no_error_log
[error]



=== TEST 9: ip.is_trusted() trusts range (ipv6)
--- SKIP: TODO
--- config
    location = /t {
        content_by_lua_block {

        }
    }
--- request
GET /t
--- response_body

--- no_error_log
[error]
