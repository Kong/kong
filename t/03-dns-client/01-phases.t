use Test::Nginx::Socket;

plan tests => repeat_each() * (blocks() * 5);

workers(6);

no_shuffle();
run_tests();

__DATA__

=== TEST 1: client supports access phase
--- config
    location = /t {
        access_by_lua_block {
            local client = require("kong.resty.dns.client")
            assert(client.init())
            local host = "localhost"
            local typ = client.TYPE_A
            local answers, err = client.resolve(host, { qtype = typ })

            if not answers then
                ngx.say("failed to resolve: ", err)
            end

            ngx.say("address name: ", answers[1].name)
        }
    }
--- request
GET /t
--- response_body
address name: localhost
--- no_error_log
[error]
dns lookup pool exceeded retries
API disabled in the context of init_worker_by_lua



=== TEST 2: client does not support init_worker phase
--- http_config eval
qq {
    init_worker_by_lua_block {
        local client = require("kong.resty.dns.client")
        assert(client.init())
        local host = "konghq.com"
        local typ = client.TYPE_A
        answers, err = client.resolve(host, { qtype = typ })
    }
}
--- config
    location = /t {
        access_by_lua_block {
            ngx.say("answers: ", answers)
            ngx.say("err: ", err)
        }
    }
--- request
GET /t
--- response_body
answers: nil
err: dns client error: 101 empty record received
--- no_error_log
[error]
dns lookup pool exceeded retries
API disabled in the context of init_worker_by_lua
