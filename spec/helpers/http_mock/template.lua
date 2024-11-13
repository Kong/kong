return [[
# if not hostname then
#   hostname = "_"
# end
# if not debug.port then
#   error("debug.port is required")
# end
# if not shm_size then
#   shm_size = "20m"
# end
daemon on;
# if not worker_num then
#   worker_num = 1
# end
worker_processes  $(worker_num);
error_log  logs/error.log info;
pid        logs/nginx.pid;
worker_rlimit_nofile 8192;

events {
  worker_connections  1024;
}

http {
  lua_shared_dict mock_logs $(shm_size);

# for dict, size in pairs(dicts or {}) do
  lua_shared_dict $(dict) $(size);
# end

  init_by_lua_block {
# if log_opts.err then
    -- disable warning of global variable
    local g_meta = getmetatable(_G)
    setmetatable(_G, nil)

    original_assert = assert -- luacheck: ignore

    local function insert_err(err)
      local err_t = ngx.ctx.err
      if not err_t then
        err_t = {}
        ngx.ctx.err = err_t
      end
      table.insert(err_t, {err, debug.traceback("", 3)})
    end

    function assert(truthy, err, ...) -- luacheck: ignore
      if not truthy and ngx.ctx then
        insert_err(err)
      end

      return original_assert(truthy, err, ...)
    end

    original_error = error -- luacheck: ignore

    function error(msg, ...) -- luacheck: ignore
      if ngx.ctx then
        insert_err(msg)
      end

      return original_error(msg, ...)
    end

    err_patched = true -- luacheck: ignore

    setmetatable(_G, g_meta)
# end
# if init then
$(init)
# end
  }

  server {
    listen 0.0.0.0:$(debug.port);
    server_name mock_debug;

    location = /status {
      stub_status;
    }

    location /logs {
      default_type application/json;

      access_by_lua_block {
        local mock_logs = ngx.shared.mock_logs

        if ngx.req.get_method() == "DELETE" then
          mock_logs:flush_all()
          return ngx.exit(204)
        end

        if ngx.req.get_method() ~= "POST" then
          return ngx.exit(405)
        end

        ngx.print("[")
        local ele, err
        repeat
          local old_ele = ele
          ele, err = mock_logs:lpop("mock_logs")
          if old_ele and ele then
            ngx.print(",", ele)
          elseif ele then
            ngx.print(ele)
          end
          if err then
            return ngx.exit(500)
          end
        until not ele
        ngx.print("]")
        ngx.exit(200)
      }
    }
  }

  server {
# for _, listen in ipairs(listens or {}) do
    listen $(listen);
# end
    server_name $(hostname);

# for _, directive in ipairs(directives or {}) do
    $(directive)

# end
# if tls then
    ssl_certificate        ../../spec/fixtures/kong_spec.crt;
    ssl_certificate_key    ../../spec/fixtures/kong_spec.key;
    ssl_protocols TLSv1.2;
    ssl_ciphers   HIGH:!aNULL:!MD5;

# end
# for location, route in pairs(routes or {}) do
    location $(location) {
# if route.directives then
      $(route.directives)

# end
# if route.access or log_opts.req then
      access_by_lua_block {
# if log_opts.req then
        -- collect request
        local method = ngx.req.get_method()
        local uri = ngx.var.request_uri
        local headers = ngx.req.get_headers(nil, true)


        ngx.req.read_body()
        local body
# if log_opts.req_body then
        -- collect body
        body = ngx.req.get_body_data()
        if not body then
          local file = ngx.req.get_body_file()
          if file then
# if log_opts.req_large_body then
            local f = io.open(file, "r")
            if f then
              body = f:read("*a")
              f:close()
            end
# else
            body = { "body is too large" }
# end -- if log_opts.req_large_body
          end
        end
# end -- if log_opts.req_body
        ngx.ctx.req = {
          method = method,
          uri = uri,
          headers = headers,
          body = body,
        }

# end -- if log_opts.req
# if route.access then
        $(route.access)
# end
      }
# end

# if route.header_filter then
      header_filter_by_lua_block {
        $(route.header)
      }

# end
# if route.content then
      content_by_lua_block {
        $(route.content)
      }

# end
# if route.body_filter or log_opts.resp_body then
      body_filter_by_lua_block {
# if route.body_filter then
        $(route.body)

# end
# if log_opts.resp_body then
        -- collect body
        ngx.ctx.resp_body = ngx.ctx.resp_body or {}
        if not ngx.arg[2] then
          table.insert(ngx.ctx.resp_body, ngx.arg[1])
        end
# end  -- if log_opts.resp_body
      }

# end
      log_by_lua_block {
# if route.log then
        $(route.log)

# end
        -- collect session data
        local cjson = require "cjson"
        local start_time = ngx.req.start_time()
        local end_time = ngx.now()

        local req = ngx.ctx.req or {}
        local resp
# if log_opts.resp then
        resp = {
          status = ngx.status,
          headers = ngx.resp.get_headers(nil, true),
          body = ngx.ctx.resp_body and table.concat(ngx.ctx.resp_body),
        }
# else -- if log_opts.resp
        resp = {}
# end  -- if log_opts.resp
        local err = ngx.ctx.err

        ngx.shared.mock_logs:rpush("mock_logs", cjson.encode({
          start_time = start_time,
          end_time = end_time,
          req = req,
          resp = resp,
          err = err,
        }))
      }
    }
# end  -- for location, route in pairs(routes)
  }
}
]]
