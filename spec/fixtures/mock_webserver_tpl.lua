return [[daemon on;
worker_processes  ${worker_num};
error_log  ${base_path}/${logs_dir}/error.log info;
pid        ${base_path}/${logs_dir}/nginx.pid;
worker_rlimit_nofile 8192;

events {
  worker_connections  1024;
}

http {
  lua_shared_dict server_values 512k;
  lua_shared_dict logs 512k;
  lua_shared_dict log_locks 512k;

  init_worker_by_lua_block {
    local resty_lock = require "resty.lock"
    _G.log_locks = resty_lock:new("log_locks")

    _G.log_record = function(ngx_req)
      local cjson = require("cjson")
      local args, err = ngx_req.get_uri_args(0)
      local key = args['key'] or "default"
      local log_locks = _G.log_locks

      if err then
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
      end

      log_locks:lock("lock")

      local logs = ngx.shared.logs:get(key) or "[]"

      if not args['do_not_log'] then
        local log = {
          time = ngx.now(),
          -- path = "/log",
          method = ngx_req.get_method(),
          headers = ngx_req.get_headers(0),
        }

        logs = cjson.decode(logs)
        table.insert(logs, log)
        logs = cjson.encode(logs)
        ngx.shared.logs:set(key, logs)
      end

      log_locks:unlock()

      return logs
    end

    local server_values = ngx.shared.server_values
# for _, prefix in ipairs(hosts) do
    if server_values:get("$(prefix)_healthy") == nil then
      server_values:set("$(prefix)_healthy", true)
      ngx.log(ngx.INFO, "Creating entries for $(prefix)_healthy")
    end

    if server_values:get("$(prefix)_timeout") == nil then
      server_values:set("$(prefix)_timeout", false)
      ngx.log(ngx.INFO, "Creating entries for $(prefix)_timeout")
    end
# end
  }

  default_type application/json;
  access_log   ${base_path}/${logs_dir}/access.log;
  sendfile     on;
  tcp_nopush   on;
  server_names_hash_bucket_size 128;

  server {
# if protocol ~= 'https' then
    listen 127.0.0.1:${http_port};
# if not disable_ipv6 then
    listen [::1]:${http_port};
#end
# else
    listen 127.0.0.1:${http_port} ssl;
# if not disable_ipv6 then
    listen [::1]:${http_port} ssl;
#end
    http2 on;

    ssl_certificate     ${cert_path}/kong_spec.crt;
    ssl_certificate_key ${cert_path}/kong_spec.key;
    ssl_protocols TLSv1.2;
    ssl_ciphers   HIGH:!aNULL:!MD5;
#end
# if check_hostname then
    server_name ${host};
#end

    location = /clear_log {
      content_by_lua_block {
        local log_locks = _G.log_locks
        log_locks:lock("lock")
        ngx.shared.logs:flush_all()
        log_locks:unlock()
        ngx.say("cleared")
      }
    }

    location = /log {
      content_by_lua_block {
        ngx.say(_G.log_record(ngx.req))
      }
    }

    location = /always_200 {
      content_by_lua_block {
        ngx.say("ok")
        return ngx.exit(ngx.HTTP_OK)
      }
    }

    location = /healthy {
      access_by_lua_block {
        local host = ngx.req.get_headers(0)["host"] or "localhost"
        local host_no_port = ngx.re.match(host, [=[([a-z0-9\-._~%!$&'()*+,;=]+@)?([a-z0-9\-._~%]+|\[[a-z0-9\-._~%!$&'()*+,;=:]+\])(:?[0-9]+)*]=])
        if host_no_port == nil then
          return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        else
          host = host_no_port[2]
          if host == "[0000:0000:0000:0000:0000:0000:0000:0001]" then
            host = "[::1]"
          end
        end
        ngx.shared.server_values:set(host .. "_healthy", true)
        ngx.shared.server_values:set(host .. "_timeout", false)
        ngx.log(ngx.INFO, "Host ", host, " is now healthy")
      }

      content_by_lua_block {
        ngx.say("server ", ngx.var.server_name, " is now healthy")
        return ngx.exit(ngx.HTTP_OK)
      }
    }

    location = /unhealthy {
      access_by_lua_block {
        local host = ngx.req.get_headers(0)["host"] or "localhost"
        local host_no_port = ngx.re.match(host, [=[([a-z0-9\-._~%!$&'()*+,;=]+@)?([a-z0-9\-._~%]+|\[[a-z0-9\-._~%!$&'()*+,;=:]+\])(:?[0-9]+)*]=])
        if host_no_port == nil then
          return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        else
          host = host_no_port[2]
          if host == "[0000:0000:0000:0000:0000:0000:0000:0001]" then
            host = "[::1]"
          end
        end
        ngx.shared.server_values:set(host .. "_healthy", false)
        ngx.log(ngx.INFO, "Host ", host, " is now unhealthy")
      }

      content_by_lua_block {
        ngx.say("server ", ngx.var.server_name, " is now unhealthy")
        return ngx.exit(ngx.HTTP_OK)
      }
    }

    location = /timeout {
      access_by_lua_block {
        local host = ngx.req.get_headers()["host"] or "localhost"
        local host_no_port = ngx.re.match(host, [=[([a-z0-9\-._~%!$&'()*+,;=]+@)?([a-z0-9\-._~%]+|\[[a-z0-9\-._~%!$&'()*+,;=:]+\])(:?[0-9]+)*]=])
        if host_no_port == nil then
          return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        else
          host = host_no_port[2]
          if host == "[0000:0000:0000:0000:0000:0000:0000:0001]" then
            host = "[::1]"
          end
        end
        ngx.shared.server_values:set(host .. "_timeout", true)
        ngx.log(ngx.INFO, "Host ", host, " is timeouting now")
      }

      content_by_lua_block {
        ngx.say("server ", ngx.var.server_name, " is timeouting now")
        return ngx.exit(ngx.HTTP_OK)
      }
    }

    location = /status {
      access_by_lua_block {
        _G.log_record(ngx.req)
        local i = require 'inspect'
        ngx.log(ngx.ERR, "INSPECT status (headers): ", i(ngx.req.get_headers(0)))
        local host = ngx.req.get_headers(0)["host"] or "localhost"
        local host_no_port = ngx.re.match(host, [=[([a-z0-9\-._~%!$&'()*+,;=]+@)?([a-z0-9\-._~%]+|\[[a-z0-9\-._~%!$&'()*+,;=:]+\])(:?[0-9]+)*]=])
        if host_no_port == nil then
          return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        else
          host = host_no_port[2]
          if host == "[0000:0000:0000:0000:0000:0000:0000:0001]" then
            host = "[::1]"
          end
        end
        local server_values = ngx.shared.server_values

        local status = server_values:get(host .. "_healthy") and
                        ngx.HTTP_OK or ngx.HTTP_INTERNAL_SERVER_ERROR

        if server_values:get(host .. "_timeout") == true then
          ngx.log(ngx.INFO, "Host ", host, " timeouting...")
          ngx.log(ngx.INFO, "[COUNT] status 599")
          ngx.sleep(4)
        else
          ngx.log(ngx.INFO, "[COUNT] status ", status)
        end

        ngx.exit(status)
      }
    }

    location / {
      access_by_lua_block {
          _G.log_record(ngx.req)
          local cjson = require("cjson")
          local server_values = ngx.shared.server_values
          local host = ngx.req.get_headers(0)["host"] or "localhost"
          local host_no_port = ngx.re.match(host, [=[([a-z0-9\-._~%!$&'()*+,;=]+@)?([a-z0-9\-._~%]+|\[[a-z0-9\-._~%!$&'()*+,;=:]+\])(:?[0-9]+)*]=])
          if host_no_port == nil then
            return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
          else
            host = host_no_port[2]
            if host == "[0000:0000:0000:0000:0000:0000:0000:0001]" then
              host = "[::1]"
            end
          end
          local status

          local status = server_values:get(host .. "_healthy") and
                        ngx.HTTP_OK or ngx.HTTP_INTERNAL_SERVER_ERROR

          if server_values:get(host .. "_timeout") == true then
            -- not this status actually, but it is used to count failures
            ngx.log(ngx.INFO, "[COUNT] slash 599")
            ngx.sleep(4)
          else
            ngx.log(ngx.INFO, "[COUNT] slash ", status)
          end

          ngx.sleep(${delay}/1000)
          ngx.exit(status)
      }
    }
  }
# if check_hostname then
  server {
    listen 127.0.0.1:${http_port} default_server;
    listen [::1]:${http_port} default_server;
    server_name _;
    return 400;
  }
# end

}
]]
