return [[
worker_processes ${{NGINX_WORKER_PROCESSES}};
daemon ${{NGINX_DAEMON}};

#--worker_rlimit_nofile ;

events {
    #--worker_connections ;
    #--multi_accept on;
}

http {
    include 'nginx-kong.conf';
}
]]
