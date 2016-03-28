return [[
worker_processes ${{NGINX_WORKER_PROCESSES}};
daemon ${{NGINX_DAEMON}};

events {
# if nginx_optimizations then
    worker_connections ${{ULIMIT}};
    multi_accept on;
# end
}

http {
    include 'nginx-kong.conf';
}
]]
