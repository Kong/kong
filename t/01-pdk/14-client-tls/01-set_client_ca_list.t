# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 6 + 4);

my $pwd = cwd();

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: calling set_client_ca_list, ca dn list is sent (using `resty.openssl.x509.chain`)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lualib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   konghq.com;
        ssl_certificate_by_lua_block {
            print("ssl cert by lua is running!")

	    local PDK = require "kong.pdk"
	    local pdk = PDK.new()
            local tls = pdk.client.tls
            local x509_lib = require "resty.openssl.x509"
            local chain_lib = require "resty.openssl.x509.chain"

            local subcafile, cafile, chain, subca, ca, suc, err
            local ca_path = "t/certs/ca.crt"
            local subca_path = "t/certs/intermediate.crt"

            suc, err = tls.request_client_certificate()
            if err then
                ngx.log(ngx.ERR, "unable to request client certificate: ", err)
                return ngx.exit(ngx.ERROR)
            end

            subcafile, err = io.open(subca_path, "r")
            if err then
                ngx.log(ngx.ERR, "unable to open file " .. subca_path .. ": ", err)
                return ngx.exit(ngx.ERROR)
            end

            cafile, err = io.open(ca_path, "r")
            if err then
                ngx.log(ngx.ERR, "unable to open file " .. ca_path .. ": ", err)
                return ngx.exit(ngx.ERROR)
            end

            chain, err = chain_lib.new()
            if err then
                ngx.log(ngx.ERR, "unable to new chain: ", err)
                return ngx.exit(ngx.ERROR)
            end

            subca, err = x509_lib.new(subcafile:read("*a"), "PEM")
            if err then
                ngx.log(ngx.ERR, "unable to read and parse the subca cert: ", err)
                return ngx.exit(ngx.ERROR)
            end
            subcafile:close()

            ca, err = x509_lib.new(cafile:read("*a"), "PEM")
            if err then
                ngx.log(ngx.ERR, "unable to read and parse the ca cert: ", err)
                return ngx.exit(ngx.ERROR)
            end
            cafile:close()

            suc, err = chain:add(subca)
            if err then
                ngx.log(ngx.ERR, "unable to add the subca cert to the chain: ", err)
                return ngx.exit(ngx.ERROR)
            end

            suc, err = chain:add(ca)
            if err then
                ngx.log(ngx.ERR, "unable to add the ca cert to the chain: ", err)
                return ngx.exit(ngx.ERROR)
            end

            suc, err = tls.set_client_ca_list(chain.ctx)
            if err then
                ngx.log(ngx.ERR, "unable to set client ca list: ", err)
                return ngx.exit(ngx.ERROR)
            end

            print("ssl cert by lua complete!")
        }
        ssl_certificate ../../certs/test.crt;
        ssl_certificate_key ../../certs/test.key;
        ssl_session_tickets off;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {
                ngx.say("impossibe to reach here")
            }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;

    location /t {
        content_by_lua_block {
            local handle = io.popen("openssl s_client -unix $TEST_NGINX_HTML_DIR/nginx.sock > /tmp/output.txt", "w")
            if not handle then
                ngx.log(ngx.ERR, "unable to popen openssl: ", err)
                return ngx.exit(ngx.ERROR)
            end
            ngx.sleep(2)
            assert(handle:write("bad request"))
            handle:close()

            handle = io.popen("grep '^Acceptable client certificate CA names$\\|^C = US,' /tmp/output.txt")
            if not handle then
                ngx.log(ngx.ERR, "unable to popen grep: ", err)
                return ngx.exit(ngx.ERROR)
            end
            ngx.print(handle:read("*a"))
            handle:close()
        }
    }

--- request
GET /t
--- response_body
Acceptable client certificate CA names
C = US, ST = California, O = Kong Testing, CN = Kong Testing Intermidiate CA
C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA

--- error_log
ssl cert by lua is running!
ssl cert by lua complete!

--- no_error_log
[error]
[alert]
[crit]



=== TEST 2: calling set_client_ca_list, ca dn list is sent (using `ngx.ssl.parse_pem_cert`)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lualib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   konghq.com;
        ssl_certificate_by_lua_block {
            print("ssl cert by lua is running!")

	    local PDK = require "kong.pdk"
	    local pdk = PDK.new()
            local tls = pdk.client.tls
            local ssl_lib = require "ngx.ssl"

            local cafile, cadata, chain, suc, err
            local ca_path = "t/certs/ca.crt"

            suc, err = tls.request_client_certificate()
            if err then
                ngx.log(ngx.ERR, "unable to request client certificate: ", err)
                return ngx.exit(ngx.ERROR)
            end

            cafile, err = io.open(ca_path, "r")
            if err then
                ngx.log(ngx.ERR, "unable to open file " .. ca_path .. ": ", err)
                return ngx.exit(ngx.ERROR)
            end

            cadata = cafile:read("*a")
            if not cadata then
                ngx.log(ngx.ERR, "unable to read file " .. ca_path)
                return ngx.exit(ngx.ERROR)
            end

            cafile:close()

            chain, err = ssl_lib.parse_pem_cert(cadata)
            if err then
                ngx.log(ngx.ERR, "unable to parse the pem ca cert: ", err)
                return ngx.exit(ngx.ERROR)
            end

            suc, err = tls.set_client_ca_list(chain)
            if err then
                ngx.log(ngx.ERR, "unable to set client ca list: ", err)
                return ngx.exit(ngx.ERROR)
            end

            print("ssl cert by lua complete!")
        }
        ssl_certificate ../../certs/test.crt;
        ssl_certificate_key ../../certs/test.key;
        ssl_session_tickets off;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {
                ngx.say("impossibe to reach here")
            }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;

    location /t {
        content_by_lua_block {
            local handle = io.popen("openssl s_client -unix $TEST_NGINX_HTML_DIR/nginx.sock > /tmp/output.txt", "w")
            if not handle then
                ngx.log(ngx.ERR, "unable to popen openssl: ", err)
                return ngx.exit(ngx.ERROR)
            end
            ngx.sleep(2)
            assert(handle:write("bad request"))
            handle:close()

            handle = io.popen("grep '^Acceptable client certificate CA names$\\|^C = US,' /tmp/output.txt")
            if not handle then
                ngx.log(ngx.ERR, "unable to popen grep: ", err)
                return ngx.exit(ngx.ERROR)
            end
            ngx.print(handle:read("*a"))
            handle:close()
        }
    }

--- request
GET /t
--- response_body
Acceptable client certificate CA names
C = US, ST = California, O = Kong Testing, CN = Kong Testing Root CA

--- error_log
ssl cert by lua is running!
ssl cert by lua complete!

--- no_error_log
[error]
[alert]
[crit]



=== TEST 3: without calling set_client_ca_list, ca dn list isn't sent
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lualib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   konghq.com;
        ssl_certificate_by_lua_block {
            print("ssl cert by lua is running!")

	    local PDK = require "kong.pdk"
	    local pdk = PDK.new()
            local tls = pdk.client.tls
            local suc, err

            suc, err = tls.request_client_certificate()
            if err then
                ngx.log(ngx.ERR, "unable to request client certificate: ", err)
                return ngx.exit(ngx.ERROR)
            end

            print("ssl cert by lua complete!")
        }
        ssl_certificate ../../certs/test.crt;
        ssl_certificate_key ../../certs/test.key;
        ssl_session_tickets off;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {
                ngx.say("impossibe to reach here")
            }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;

    location /t {
        content_by_lua_block {
            local handle = io.popen("openssl s_client -unix $TEST_NGINX_HTML_DIR/nginx.sock > /tmp/output.txt", "w")
            if not handle then
                ngx.log(ngx.ERR, "unable to popen openssl: ", err)
                return ngx.exit(ngx.ERROR)
            end
            ngx.sleep(2)
            assert(handle:write("bad request"))
            handle:close()

            handle = io.popen("grep '^No client certificate CA names sent$' /tmp/output.txt")
            if not handle then
                ngx.log(ngx.ERR, "unable to popen grep: ", err)
                return ngx.exit(ngx.ERROR)
            end
            ngx.print(handle:read("*a"))
            handle:close()
        }
    }

--- request
GET /t
--- response_body
No client certificate CA names sent

--- error_log
ssl cert by lua is running!
ssl cert by lua complete!

--- no_error_log
[error]
[alert]
[crit]



=== TEST 4: calling set_client_ca_list with an empty chain, no real effect, ca dn list isn't sent
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;lualib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   konghq.com;
        ssl_certificate_by_lua_block {
            print("ssl cert by lua is running!")

	    local PDK = require "kong.pdk"
	    local pdk = PDK.new()
            local tls = pdk.client.tls
            local chain_lib = require "resty.openssl.x509.chain"

            local chain, suc, err

            suc, err = tls.request_client_certificate()
            if err then
                ngx.log(ngx.ERR, "unable to request client certificate: ", err)
                return ngx.exit(ngx.ERROR)
            end

            chain, err = chain_lib.new()
            if err then
                ngx.log(ngx.ERR, "unable to new chain: ", err)
                return ngx.exit(ngx.ERROR)
            end

            suc, err = tls.set_client_ca_list(chain.ctx)
            if err then
                ngx.log(ngx.ERR, "unable to set client ca list: ", err)
                return ngx.exit(ngx.ERROR)
            end

            print("ssl cert by lua complete!")
        }
        ssl_certificate ../../certs/test.crt;
        ssl_certificate_key ../../certs/test.key;
        ssl_session_tickets off;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {
                ngx.say("impossibe to reach here")
            }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;

    location /t {
        content_by_lua_block {
            local handle = io.popen("openssl s_client -unix $TEST_NGINX_HTML_DIR/nginx.sock > /tmp/output.txt", "w")
            if not handle then
                ngx.log(ngx.ERR, "unable to popen openssl: ", err)
                return ngx.exit(ngx.ERROR)
            end
            ngx.sleep(2)
            assert(handle:write("bad request"))
            handle:close()

            handle = io.popen("grep '^No client certificate CA names sent$' /tmp/output.txt")
            if not handle then
                ngx.log(ngx.ERR, "unable to popen grep: ", err)
                return ngx.exit(ngx.ERROR)
            end
            ngx.print(handle:read("*a"))
            handle:close()
        }
    }

--- request
GET /t
--- response_body
No client certificate CA names sent

--- error_log
ssl cert by lua is running!
ssl cert by lua complete!

--- no_error_log
[error]
[alert]
[crit]
