return [[
> if nginx_user then
user ${{NGINX_USER}};
> end
worker_processes ${{NGINX_WORKER_PROCESSES}};
daemon ${{NGINX_DAEMON}};

pid pids/nginx.pid;
error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

> if nginx_optimizations then
worker_rlimit_nofile ${{WORKER_RLIMIT}};
> end

events {
> if nginx_optimizations then
    worker_connections ${{WORKER_CONNECTIONS}};
    multi_accept on;
> end
}

http {
> if #proxy_listeners > 0 or #admin_listeners > 0 then
    include 'nginx-kong.conf';
> end
}

> if #stream_listeners > 0 then
stream {
    include 'nginx-kong-stream.conf';
}
> end
]]
