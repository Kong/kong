use Test::Nginx::Socket;

plan tests => repeat_each() * (blocks() * 5);

workers(1);

no_shuffle();
run_tests();

__DATA__

=== TEST 1: stale result triggers async timer
--- config
    location = /t {
        access_by_lua_block {
            -- init
            local client = require("kong.resty.dns.client")
            assert(client.init({
                nameservers = { "127.0.0.53" },
                hosts = {}, -- empty tables to parse to prevent defaulting to /etc/hosts
                resolvConf = {}, -- and resolv.conf files
                order = { "A" },
                validTtl = 1,
            }))

            local host = "konghq.com"
            local typ = client.TYPE_A

            -- first time

            local answers, err, try_list = client.resolve(host, { qtype = typ })
            if not answers then
                ngx.say("failed to resolve: ", err)
                return
            end
            ngx.say("first address name: ", answers[1].name)
            ngx.say("first try_list: ", tostring(try_list))

            -- sleep to wait for dns record to become stale
            ngx.sleep(1.5)

            -- second time: use stale result and trigger async timer

            answers, err, try_list = client.resolve(host, { qtype = typ })
            if not answers then
                ngx.say("failed to resolve: ", err)
                return
            end
            ngx.say("second address name: ", answers[1].name)
            ngx.say("second try_list: ", tostring(try_list))

            -- third time: use stale result and find triggered async timer

            answers, err, try_list = client.resolve(host, { qtype = typ })
            if not answers then
                ngx.say("failed to resolve: ", err)
                return
            end
            ngx.say("third address name: ", answers[1].name)
            ngx.say("third try_list: ", tostring(try_list))
        }
    }
--- request
GET /t
--- response_body
first address name: konghq.com
first try_list: ["(short)konghq.com:1 - cache-miss","konghq.com:1 - cache-miss/querying"]
second address name: konghq.com
second try_list: ["(short)konghq.com:1 - cache-hit/stale","konghq.com:1 - cache-hit/stale/scheduled"]
third address name: konghq.com
third try_list: ["(short)konghq.com:1 - cache-hit/stale","konghq.com:1 - cache-hit/stale/in progress (async)"]
--- no_error_log
[error]
dns lookup pool exceeded retries
API disabled in the context of init_worker_by_lua
